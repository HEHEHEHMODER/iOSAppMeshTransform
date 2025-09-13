//
//  ContentView.swift
//  iOSAppMeshTransform
//
//  Created by Gavin Nelson on 9/12/25.
//

import SwiftUI

struct ContentView: View {
	
	@State private var isOpen = false
	@State private var duration: Double = 0.4
	@State private var manualProgress: Float = 0.0
	
	private let startSize = CGSize(width: 75, height: 75)
	private let openRadius: CGFloat = 79
	
	var body: some View {
		GeometryReader { geo in
			
			// Full device screen size
			let screen = CGSize(width: geo.size.width, height: geo.size.height)
			
			// TODO: Generalize this
			let startOrigin = CGPoint(
				x: 29,
				y: screen.height - startSize.height - 29
			)
			let startRect = CGRect(origin: startOrigin, size: startSize)
			let cornerFrom = 25
			
			ZStack {
				Color.black
				wallpaper
				Image("applenotes")
					.frame(width: screen.width, height: screen.height)
					.layerEffect(
						ShaderLibrary.appMeshTransform(
							.boundingRect,
							.float4(
								Float(startRect.minX), Float(startRect.minY),
								Float(startRect.width), Float(startRect.height)
							),
							.float(Float(cornerFrom)),
							.float(Float(openRadius)),
							.float(manualProgress),
							.float(0.35)
						),
						maxSampleOffset: .zero
					)
					.allowsHitTesting(false)
				Image("appicon")
					.resizable()
					.aspectRatio(contentMode: .fill)
					.frame(width: screen.width, height: screen.height)
					.modifier(IconOpacityByProgressModifier(
						progress: Double(manualProgress),
						isOpen: isOpen,
						openThreshold: 0.4,
						closeThreshold: 0.6
					))
					.layerEffect(
						ShaderLibrary.appMeshTransform(
							.boundingRect,
							.float4(
								Float(startRect.minX), Float(startRect.minY),
								Float(startRect.width), Float(startRect.height)
							),
							.float(Float(cornerFrom)),
							.float(Float(openRadius)),
							.float(manualProgress),
							.float(0.35)
						),
						maxSampleOffset: .zero
					)
					.allowsHitTesting(false)
				
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.contentShape(Rectangle())
			
			// Drive progress with a vertical drag gesture
			// This was quickly vibecoded to replace my ugly slider and there's probably a nicer way of doing it...
			.simultaneousGesture(
				DragGesture()
					.onChanged { value in
						let h = screen.height
						let y = value.location.y
						// Bottom padding before progress starts increasing
						let padding: CGFloat = 120
						// Progress 0 at this y
						let y0 = h - padding
						// Progress 1 at mid-screen
						let y1 = h * 0.4
						let denom = max(1, y0 - y1)
						let normalized = (y0 - y) / denom
						manualProgress = Float(min(max(normalized, 0.0), 1.0))
					}
			)
			// Drive progress with a tap
			.onTapGesture {
				withAnimation(.smooth(duration: duration)) {
					
					isOpen.toggle()
					manualProgress = isOpen ? 1.0 : 0.0
				}
			}
		}
		.statusBarHidden()
		.ignoresSafeArea()
	}
	
	var wallpaper: some View {
		Image("lily")
			.resizable()
	}
}

// TODO: there must be a better way to do this
private struct IconOpacityByProgressModifier: AnimatableModifier {
	var progress: Double
	var isOpen: Bool
	var openThreshold: Double = 0.4
	var closeThreshold: Double = 0.6
	
	var animatableData: Double {
		get { progress }
		set { progress = newValue }
	}
	
	func body(content: Content) -> some View {
		let t = isOpen ? openThreshold : closeThreshold
		// Linear clamp: 1 at 0, 0 by t
		let opacity = max(0.0, min(1.0, (t - progress) / (t == 0 ? 1 : t)))
		return content.opacity(opacity)
	}
}


#Preview {
	ContentView()
}
