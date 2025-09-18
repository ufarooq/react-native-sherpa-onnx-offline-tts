// TTSManager.swift

import Foundation
import AVFoundation
import React

// Define a protocol for volume updates
protocol AudioPlayerDelegate: AnyObject {
    func didUpdateVolume(_ volume: Float)
}

@objc(TTSManager)
class TTSManager: RCTEventEmitter, AudioPlayerDelegate {
    private var tts: SherpaOnnxOfflineTtsWrapper?
    private var realTimeAudioPlayer: AudioPlayer?
    private var recognizer: SherpaOnnxOfflineRecognizer?
    private var sttSampleRate: Int = 16000
    private var audioEngine: AVAudioEngine?
    private var capturedSamples: [Float] = []
    
    override init() {
        super.init()
        // Optionally, initialize AudioPlayer here if needed
    }
    
    // Required for RCTEventEmitter
    override static func requiresMainQueueSetup() -> Bool {
        return true
    }
    
    // Specify the events that can be emitted
    override func supportedEvents() -> [String]! {
        return ["VolumeUpdate"]
    }
    
    // Initialize TTS and Audio Player
    @objc(initializeTTS:channels:modelId:)
    func initializeTTS(_ sampleRate: Double, channels: Int, modelId: String) {
        self.realTimeAudioPlayer = AudioPlayer(sampleRate: sampleRate, channels: AVAudioChannelCount(channels))
        self.realTimeAudioPlayer?.delegate = self // Set delegate to receive volume updates
        self.tts = createOfflineTts(modelId: modelId)
    }

    // Initialize streaming STT
    @objc(initializeSTT:)
    func initializeSTT(_ modelId: String) {
        guard let data = modelId.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let encoder = json["encoder"] as? String ?? ""
        let decoder = json["decoder"] as? String ?? ""
        let joiner = json["joiner"] as? String ?? ""
        let tokens = json["tokens"] as? String ?? ""
        sttSampleRate = json["sampleRate"] as? Int ?? 16000

        var model = sherpaOnnxOfflineModelConfig(
            tokens: tokens,
            transducer: sherpaOnnxOfflineTransducerModelConfig(
                encoder: encoder,
                decoder: decoder,
                joiner: joiner
            ),
            numThreads: 1,
            provider: "cpu",
            debug: 1
        )
        let feat = sherpaOnnxFeatureConfig(sampleRate: sttSampleRate)
        var cfg = sherpaOnnxOfflineRecognizerConfig(
            featConfig: feat,
            modelConfig: model,
            decodingMethod: "greedy_search"
        )
        recognizer = SherpaOnnxOfflineRecognizer(config: &cfg)
    }

    @objc func startRecognition() {
        audioEngine = AVAudioEngine()
        capturedSamples.removeAll()
        guard let engine = audioEngine else { return }
        guard recognizer != nil else { return }
        let input = engine.inputNode
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sttSampleRate), channels: 1, interleaved: false)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            let count = Int(buffer.frameLength)
            if let data = buffer.floatChannelData?[0] {
                let samples = Array(UnsafeBufferPointer(start: data, count: count))
                self.capturedSamples.append(contentsOf: samples)
            }
        }
        engine.prepare()
        try? engine.start()
    }

    @objc func feedAudio(_ data: String) {
        guard let bytes = Data(base64Encoded: data) else { return }
        let count = bytes.count / 2
        var samples = [Float]()
        samples.reserveCapacity(count)
        bytes.withUnsafeBytes { buf in
            for i in 0..<count {
                let val = buf.load(fromByteOffset: i*2, as: Int16.self)
                samples.append(Float(val) / 32768.0)
            }
        }
        capturedSamples.append(contentsOf: samples)
    }

    @objc func stopRecognition(_ resolver: RCTPromiseResolveBlock, rejecter: RCTPromiseRejectBlock) {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        guard let rec = recognizer else {
            rejecter("NOT_READY", "Recognizer not ready", nil)
            return
        }
        let result = rec.decode(samples: capturedSamples, sampleRate: sttSampleRate)
        capturedSamples.removeAll()
        resolver(result.text)
    }

    @objc func deinitializeSTT() {
        audioEngine?.stop()
        audioEngine = nil
        recognizer = nil
        capturedSamples.removeAll()
    }

    // Generate audio and play in real-time
    @objc(generateAndPlay:sid:speed:resolver:rejecter:)
    func generateAndPlay(_ text: String, sid: Int, speed: Double, resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedText.isEmpty else {
            rejecter("EMPTY_TEXT", "Input text is empty", nil)
            return
        }
        
        // Split the text into manageable sentences
        let sentences = splitText(trimmedText, maxWords: 15)
        
        for sentence in sentences {
            let processedSentence = sentence.hasSuffix(".") ? sentence : "\(sentence)."
            generateAudio(for: processedSentence, sid: sid, speed: speed)
        }
        
        resolver("Audio generated and played successfully")
    }

    /// Splits the input text into sentences with a maximum of `maxWords` words.
    /// It prefers to split at a period (.), then a comma (,), and finally forcibly after `maxWords`.
    ///
    /// - Parameters:
    ///   - text: The input text to split.
    ///   - maxWords: The maximum number of words per sentence.
    /// - Returns: An array of sentence strings.
    func splitText(_ text: String, maxWords: Int) -> [String] {
        var sentences: [String] = []
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        var currentIndex = 0
        let totalWords = words.count
        
        while currentIndex < totalWords {
            // Determine the range for the current chunk
            let endIndex = min(currentIndex + maxWords, totalWords)
            var chunk = words[currentIndex..<endIndex].joined(separator: " ")
            
            // Search for the last period within the chunk
            if let periodRange = chunk.range(of: ".", options: .backwards) {
                let sentence = String(chunk[..<periodRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                sentences.append(sentence)
                currentIndex += sentence.components(separatedBy: .whitespacesAndNewlines).count
            }
            // If no period, search for the last comma
            else if let commaRange = chunk.range(of: ",", options: .backwards) {
                let sentence = String(chunk[..<commaRange.upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                sentences.append(sentence)
                currentIndex += sentence.components(separatedBy: .whitespacesAndNewlines).count
            }
            // If neither, forcibly break after maxWords
            else {
                sentences.append(chunk.trimmingCharacters(in: .whitespacesAndNewlines))
                currentIndex += maxWords
            }
        }
        
        return sentences
    }
    
    // Helper function to generate and play audio
    private func generateAudio(for text: String, sid: Int, speed: Double) {
        print("Generating audio for \(text)")
        let startTime = Date()
        guard let audio = tts?.generate(text: text, sid: sid, speed: Float(speed)) else {
            print("Error: TTS was never initialised")
            return
        }
        let endTime = Date()
        let generationTime = endTime.timeIntervalSince(startTime)
        print("Time taken for TTS generation: \(generationTime) seconds")
        
        realTimeAudioPlayer?.playAudioData(from: audio)
    }
    
    // Clean up resources
    @objc func deinitialize() {
        self.realTimeAudioPlayer?.stop()
        self.realTimeAudioPlayer = nil
        self.tts = nil
        deinitializeSTT()
    }
    
    // MARK: - AudioPlayerDelegate Method
    
    func didUpdateVolume(_ volume: Float) {
        // Emit the volume to JavaScript
        sendEvent(withName: "VolumeUpdate", body: ["volume": volume])
    }
}
