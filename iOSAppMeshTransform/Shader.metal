//
//  Shader.metal
//  iOSAppMeshTransform
//
//  Created by Gavin Nelson on 9/12/25.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

constant float PI = 3.14159265359;

float mapRange(float inMin, float inMax, float outMin, float outMax, float value) {
	return ((value - inMin) * (outMax - outMin) / (inMax - inMin) + outMin);
}

// Rounded Rectangle SDF (unused)
inline float signedDistanceToRoundedRect(float2 point, float2 halfExtents, float cornerRadius) {
	float2 offsetFromEdges = abs(point) - halfExtents + cornerRadius;
	float outsideDistance = length(max(offsetFromEdges, 0.0));
	float insideOffset = min(max(offsetFromEdges.x, offsetFromEdges.y), 0.0);
	return outsideDistance + insideOffset - cornerRadius;
}

// Superellipse SDF (~vibecoded~)

// Generalizes the classic rounded-rectangle by replacing the circular arc with an L^n superellipse.
// For n=2 this is identical to the standard rounded-rect SDF with radius r.
inline float signedDistanceToSuperRoundedRect(float2 point, float2 halfExtents, float r, float n) {
	// Shift coordinate so the inner core rectangle (without corners) is at q <= 0
	float2 q = abs(point) - halfExtents + r;

	// Outside corner region: use L^n norm instead of Euclidean, scaled by r
	float2 k = max(q, 0.0);
	float kn = pow(pow(k.x / max(r, 1e-6), n) + pow(k.y / max(r, 1e-6), n), 1.0 / n);
	float outside = max(r, 0.0) * (kn - 1.0);

	// Inside rectangle region: same as classic SDF
	float inside = min(max(q.x, q.y), 0.0);

	return outside + inside;
}



[[ stitchable ]] half4 appMeshTransform(float2 position, SwiftUI::Layer layer, float4 bounds, float4 fromRect, float cornerFrom, float cornerTo, float progress, float intensity) {
	
	// Bounds = x, y, width, height
	float2 canvasSize = float2(bounds[2], bounds[3]);
	
	// End state = full screen cover
	float4 endRect = float4(0.0, 0.0, canvasSize.x, canvasSize.y);
	
	
	// Normalize y to 0 -> 1 range
	float normalizedY = position.y / canvasSize.y;
	
	// Apply intensity effect based on vertical position (top expands faster)
	float progressEffect = mapRange(0, 1, 1.0, intensity, normalizedY);
	
	// Interpolate from starting rectangle to end rectangle with a power curve affected by the intensity value passed in
	// Higher intensity = the top of the rectangle will get further along in the animation before the end even starts
	// This is how we get that cool skewed motion
	float4 currentRect = mix(fromRect, endRect, pow(progress, 1.0 / (progressEffect)));
	
	// Interpolate the corner radius from start to end with another hardcoded value that looked right ish here
	// The corners in the iOS transform seemed to increase with a much faster curve than the rectangle
	float cornerProgress = pow(progress, 0.7);
	float cornerRadius = mix(cornerFrom, cornerTo, cornerProgress);

	// Jump a little bit towards the center of the screen before undoing that offset
	// Similar to an Arc Transition from Origami that drives an offset value
	// Calculate starting rect center
	float2 startCenter = float2(fromRect.x + fromRect.z * 0.5, fromRect.y + fromRect.w * 0.5);
	// Calculate screen center point
	float2 screenCenter = canvasSize * 0.5;
	// Direction vector scaled by factors
	float2 offsetDirection = (screenCenter - startCenter) * float2(0.2, 0.4);
	// Sine wave creates arc motion 0 -> 1 -> 0
	float arcAmount = sin(progress * PI);
	// Apply arc offset to rectangle position
	currentRect.xy += offsetDirection * arcAmount;

	
	// Getting the center of the rectangle relative to the screen so we can pass it to the SDF
	// Convert world position to local rectangle coordinates
	float2 rectOrigin = float2(currentRect.x, currentRect.y);
	// Note: drives me crazy that z = width and w = height
	float2 rectSize = float2(currentRect.z, currentRect.w);
	// Current rectangle center point at this point in the animation
	float2 currentCenter = rectOrigin + rectSize * 0.5;
	// Turned into local coordinates relative to the position currently being sampled
	float2 localPosition = position - currentCenter;

	
	// Calculate skew effect that bulges corner toward screen center
	// Half-width and half-height for SDF calculation
	float2 halfExtents = rectSize * 0.5;
	// Determine skew direction (left or right)
	float skewDirection = screenCenter.x > startCenter.x ? 1.0 : -1.0;
	// Make the skew an arc transition
	float skewAmount = sin(progress * PI) * 35.0;
	// 0 at top, 1 at bottom
	float verticalInfluence = (localPosition.y + halfExtents.y) / (halfExtents.y * 2.0);
	// 0 at left, 1 at right
	float horizontalInfluence = (localPosition.x + halfExtents.x) / (halfExtents.x * 2.0);
	// Flip influence for leftward skew
	if (skewDirection < 0.0) horizontalInfluence = 1.0 - horizontalInfluence;
	// Calculate final skew amount
	float skewOffset = skewAmount * (1.0 - verticalInfluence) * horizontalInfluence * 1.38 * skewDirection;
	
	// Generate rounded rectangle mask with skew distortion
	// Apply skew to X coordinate only
	float2 skewedPosition = float2(localPosition.x - skewOffset, localPosition.y);
	// Use superellipse-rounded rectangle with same cornerRadius semantics (n=2 -> classic)
	float n = 2.6; // fully circular fillet; increase for boxier, >2 squircle
	float distance = signedDistanceToSuperRoundedRect(skewedPosition, halfExtents, cornerRadius, n);
	// Convert distance to smooth 0-1 mask
	float mask = smoothstep(0.5, -0.5, distance);

	// Sample source image with scaling and skew distortion applied
	// Start with local position
	float2 skewedSamplePos = localPosition;
	// Apply same skew to sampling coordinates
	skewedSamplePos.x -= skewOffset;
	// Convert to 0-1 normalized coordinates
	float2 normalizedPos = (skewedSamplePos + halfExtents) / rectSize;
	// Scale to canvas size and clamp bounds
	float2 sourcePos = clamp(normalizedPos * canvasSize, float2(0.0), canvasSize - 1.0);
	// Sample source image at transformed coordinates
	half4 sourceColor = layer.sample(sourcePos);
	// Return masked and scaled image
	return half4(sourceColor.rgb * mask, sourceColor.a * mask);
}
