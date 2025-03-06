//
//  AIVideoDemoApp.swift
//  AIVideoDemo
//
//  Created by Martin Mitrevski on 6.3.25.
//

import SwiftUI
import StreamVideo
import StreamVideoSwiftUI

@main
struct AIVideoDemoApp: App {
    
    private let baseURL = "http://localhost:3000"
    
    @State var streamVideo: StreamVideo?
    @State var call: Call?
    @State var credentials: Credentials?
    @State var connectTask: Task<Void, Error>?
    @State var callState: AICallState = .idle

    var body: some Scene {
        WindowGroup {
            ZStack {
                if callState == .active, let call {
                    AISpeakingView(callState: call.state)
                        .overlay(
                            VStack {
                                Spacer()
                                VStack {
                                    HStack {
                                        Spacer()
                                        StatelessHangUpIconView(call: call) {
                                            call.leave()
                                            self.call = nil
                                            self.callState = .idle
                                        }
                                    }
                                }
                                .padding()
                            }
                        )
                        .id(call.cId)
                } else if callState == .joining {
                    HStack {
                        Text("Waiting for AI agent to join...")
                        ProgressView()
                    }
                } else {
                    Button {
                        guard callState == .idle else { return }
                        Task {
                            try await joinCall()
                        }
                    } label: {
                        Text("Click to talk to AI")
                            .padding()
                    }
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.edgesIgnoringSafeArea(.all))
            .onAppear {
                guard connectTask == nil else { return }
                connectTask = Task {
                    try await connect()
                }
            }
        }
    }
    
    func fetchCredentials() async throws -> Credentials {
        let urlSession = URLSession.shared
        let url = URL(string: "\(baseURL)/credentials")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let data = try await urlSession.data(for: request).0 as Data
        return try JSONDecoder().decode(Credentials.self, from: data)
    }
    
    func connect() async throws {
        let credentials = try await fetchCredentials()
        let user = User(id: credentials.userId)

        let streamVideo = StreamVideo(
            apiKey: credentials.apiKey,
            user: user,
            token: .init(rawValue: credentials.token)
        )
            
        self.streamVideo = streamVideo
        self.credentials = credentials
            
        try await streamVideo.connect()
    }
    
    func joinCall() async throws {
        do {
            self.callState = .joining
            _ = await connectTask?.result
            guard let credentials, let streamVideo else { return }
            self.call = streamVideo.call(
                callType: credentials.callType,
                callId: credentials.callId
            )
            Task {
                try await connectAI(callType: credentials.callType, callId: credentials.callId)
            }
            try await call?.join(
                create: true
            )
            self.callState = .active
        } catch {
            print(error)
            self.callState = .idle
        }
    }

    func connectAI(callType: String, callId: String) async throws {
        let urlSession = URLSession.shared
        let url = URL(string: "\(baseURL)/\(callType)/\(callId)/connect")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        _ = try await urlSession.data(for: request)
    }
}

struct Credentials: Codable {
    let apiKey: String
    let token: String
    let callType: String
    let callId: String
    let userId: String
}

enum AICallState {
    case idle
    case joining
    case active
}

struct AISpeakingView: View {
    private let agentId = "lucy"
    
    @ObservedObject var callState: CallState
    
    @State var amplitude: CGFloat = 0.0
    @State var audioLevels = [Float]()
    @State var speakerState: AISpeakerState = .idle
        
    var body: some View {
        GlowView(amplitude: amplitude, gradientColors: speakerState.gradientColors)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(Color.black)
            .onChange(of: callState.activeSpeakers) { oldSpeakers, newSpeakers in
                if let speaker = newSpeakers.first(where: { participant in
                    participant.userId.contains(agentId)
                }) {
                    if speakerState != .aiSpeaking {
                        self.speakerState = .aiSpeaking
                    }
                    self.audioLevels = speaker.audioLevels
                        .map { value in
                            value / Float(Int.random(in: 1...3))
                        }
                } else if let speaker = newSpeakers.first(where: { $0.id == callState.localParticipant?.id }) {
                    if speakerState != .userSpeaking {
                        self.speakerState = .userSpeaking
                    }
                    self.audioLevels = speaker.audioLevels
                } else {
                    self.speakerState = .idle
                    self.audioLevels = []
                }
                self.amplitude = computeSingleAmplitude(from: audioLevels)
            }
    }
    
    func computeSingleAmplitude(from levels: [Float]) -> CGFloat {
        let normalized = normalizePeak(levels)
        guard !normalized.isEmpty else { return 0 }
        
        let sum = normalized.reduce(0, +)
        let average = sum / Float(normalized.count)
        return CGFloat(average)
    }
    
    func normalizePeak(_ levels: [Float]) -> [Float] {
        // 1) Find the peak (largest absolute value)
        guard let maxLevel = levels.map({ abs($0) }).max(), maxLevel > 0 else {
            return levels // Avoid dividing by zero if empty or all zeros
        }
        
        // 2) Divide each sample by the peak
        return levels.map { $0 / maxLevel }
    }
}

enum AISpeakerState {
    case aiSpeaking
    case userSpeaking
    case idle
}

extension AISpeakerState {
    var gradientColors: [Color] {
        switch self {
        case .userSpeaking:
            return [
                Color.red,
                Color.red.opacity(0.0)
            ]
        default:
            return [
                Color(red: 0.0, green: 0.976, blue: 1.0),
                Color(red: 0.0, green: 0.227, blue: 1.0, opacity: 0.0)
            ]
        }
    }
}

struct GlowView: View {
    /// Normalized audio level [0.0 ... 1.0]
    let amplitude: CGFloat
    let gradientColors: [Color]
    
    @State private var time: CGFloat = 0
    @State private var rotationAngle: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // LAYER 1 (Outer)
                glowLayer(
                    baseRadiusMin: 150,   // radius at amplitude=0
                    baseRadiusMax: 250,  // radius at amplitude=1
                    blurRadius: 60,
                    baseOpacity: 0.35,
                    scaleRange: 0.3,   // how much amplitude grows it
                    waveRangeMin: 0.2, // bigger morph at low amplitude
                    waveRangeMax: 0.02, // smaller morph at high amplitude
                    geoSize: geo.size,
                    gradientColors: gradientColors
                )
                
                // LAYER 2 (Mid)
                glowLayer(
                    baseRadiusMin: 100,
                    baseRadiusMax: 150,
                    blurRadius: 40,
                    baseOpacity: 0.55,
                    scaleRange: 0.3,
                    waveRangeMin: 0.15,
                    waveRangeMax: 0.03,
                    geoSize: geo.size,
                    gradientColors: gradientColors
                )
                
                // LAYER 3 (Bright Core)
                glowLayer(
                    baseRadiusMin: 50,
                    baseRadiusMax: 100,
                    blurRadius: 20,
                    baseOpacity: 0.9,
                    scaleRange: 0.5,
                    waveRangeMin: 0.35,
                    waveRangeMax: 0.05,
                    geoSize: geo.size,
                    gradientColors: gradientColors
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // Rotate the entire glow. This ensures a unified rotation “centered” animation.
            .rotationEffect(.degrees(Double(rotationAngle)))
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
        // Animate amplitude changes
        .animation(.easeInOut(duration: 0.2), value: amplitude)
        .onAppear {
            // Continuous rotation over ~10s
            let spinDuration: CGFloat = 10
            withAnimation(.linear(duration: Double(spinDuration)).repeatForever(autoreverses: false)) {
                rotationAngle = 360
            }
            
            // CADisplayLink for smooth ~60fps; we keep `time` in [0..1] to loop seamlessly
            let displayLink = CADisplayLink(target: DisplayLinkProxy { dt in
                let speed: CGFloat = 0.05
                let next = time + speed * CGFloat(dt)
                time = next.truncatingRemainder(dividingBy: 1.0)
            }, selector: #selector(DisplayLinkProxy.tick(_:)))
            displayLink.add(to: .main, forMode: .common)
        }
    }
    
    /// - `baseRadiusMin` / `baseRadiusMax`: radius shrinks/grows with amplitude
    /// - `waveRangeMin` / `waveRangeMax`: morphing is stronger at low amplitude, weaker at high amplitude
    private func glowLayer(
        baseRadiusMin: CGFloat,
        baseRadiusMax: CGFloat,
        blurRadius: CGFloat,
        baseOpacity: CGFloat,
        scaleRange: CGFloat,
        waveRangeMin: CGFloat,
        waveRangeMax: CGFloat,
        geoSize: CGSize,
        gradientColors: [Color]
    ) -> some View {
        
        // The actual radius = lerp from min->max based on amplitude
        let baseRadius = lerp(a: baseRadiusMin, b: baseRadiusMax, t: amplitude)
        
        // The waveRange also “lerps,” but we want big wave at low amplitude => waveRangeMin at amplitude=1
        // => just invert the parameter. Another approach: waveRange = waveRangeMax + (waveRangeMin-waveRangeMax)*(1 - amplitude).
        let waveRange = lerp(a: waveRangeMax, b: waveRangeMin, t: (1 - amplitude))
        
        let gradient = RadialGradient(
            gradient: Gradient(stops: [
                .init(color: gradientColors[0], location: 0.0),
                .init(color: gradientColors[1], location: 1.0)
            ]),
            center: .center,
            startRadius: 0,
            endRadius: baseRadius
        )
        
        // Subtle elliptical warping from sin/cos
        let shapeWaveSin = sin(2 * .pi * time)
        let shapeWaveCos = cos(2 * .pi * time)
        
        // scale from amplitude
        let amplitudeScale = 1.0 + scaleRange * amplitude
        
        // final x/y scale => merges amplitude + wave
        let xScale = amplitudeScale + waveRange * shapeWaveSin
        let yScale = amplitudeScale + waveRange * shapeWaveCos
        
        return Ellipse()
            .fill(gradient)
            .opacity(baseOpacity)
            .scaleEffect(x: xScale, y: yScale)
            .blur(radius: blurRadius)
            .frame(width: geoSize.width, height: geoSize.height)
    }
    
    // Linear interpolation
    private func lerp(a: CGFloat, b: CGFloat, t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }
}

// MARK: - CADisplayLink Helper
fileprivate class DisplayLinkProxy {
    private let tickHandler: (CFTimeInterval) -> Void
    init(_ handler: @escaping (CFTimeInterval) -> Void) { self.tickHandler = handler }
    @objc func tick(_ link: CADisplayLink) { tickHandler(link.duration) }
}
