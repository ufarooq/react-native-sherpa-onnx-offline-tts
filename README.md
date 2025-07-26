# react-native-sherpa-onnx-offline-tts

A lightweight React Native wrapper around [Sherpa‑ONNX](https://github.com/k2-fsa/sherpa-onnx) that lets you run **100 % offline Text‑to‑Speech** and **Speech‑to‑Text** on iOS and Android.

---

## ✨ Features

| | |
|---|---|
| 🔊 **Offline** – all synthesis happens on‑device, no network needed | ⚡ **Fast** – real‑time (or faster) generation on modern phones |
| 🎙️ **Natural voices** – drop‑in support for Piper / VITS ONNX models | 🛠️ **Simple API** – TTS & STT with a handful of async methods |

---

## 📦 Installation

```bash
# Add the library
npm install react-native-sherpa-onnx-offline-tts
# or
yarn add react-native-sherpa-onnx-offline-tts

# iOS only\	npx pod-install
```

> **Minimum versions**  |  Android 5.0 (API 21) • iOS 11

---

## 🚀 Quick Start

1. **Choose a model** – grab any [Piper](https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-ryan-medium.tar.bz2) voice ZIP (e.g. `vits-piper-en_US-ryan-medium.zip`) and host it yourself or bundle it with the app.
2. **Download & unzip** the archive into your app’s sandbox (the example below uses **react‑native‑fs** & **react‑native‑zip‑archive**).
3. **Create a config JSON** with absolute paths to `*.onnx`, `tokens.txt`, and the `espeak-ng-data` folder.
4. **Initialize**, then generate or stream speech.

```tsx
import TTSManager from 'react-native-sherpa-onnx-offline-tts';
import RNFS from 'react-native-fs';
import { unzip } from 'react-native-zip-archive';

const MODEL_URL =
  'https://example.com/vits-piper-en_US-ryan-medium.zip';

async function setupTTS() {
  const archive = `${RNFS.DocumentDirectoryPath}/vits.zip`;
  const extractRoot = `${RNFS.DocumentDirectoryPath}/extracted`;

  // 1️⃣  Download if missing
  if (!(await RNFS.exists(archive))) {
    await RNFS.downloadFile({ fromUrl: MODEL_URL, toFile: archive }).promise;
  }

  // 2️⃣  Unpack if first run
  if (!(await RNFS.exists(`${extractRoot}/vits-piper-en_US-ryan-medium`))) {
    await unzip(archive, extractRoot);
  }

  // 3️⃣  Point the engine to the files
  const base = `${extractRoot}/vits-piper-en_US-ryan-medium`;
  const cfg = {
    modelPath: `${base}/en_US-ryan-medium.onnx`,
    tokensPath: `${base}/tokens.txt`,
    dataDirPath: `${base}/espeak-ng-data`,
  };

  // 4️⃣  Initialise (only once per session)
  await TTSManager.initialize(JSON.stringify(cfg));
}

async function sayHello() {
  const text = 'Hello world – spoken entirely offline!';
  const speakerId = 0;   // Piper uses 0 for single‑speaker models
  const speed = 1.0;     // 1 == default, < 1 slower, > 1 faster

  await TTSManager.generateAndPlay(text, speakerId, speed);
}
```

---

## 📚 API Reference

| Method | Signature | Description |
|--------|-----------|-------------|
| **initialize** | `(modelConfigJson: string): Promise<void>` | Must be called once before any synthesis. Pass a JSON string with `modelPath`, `tokensPath`, `dataDirPath`. |
| **generate** | `(text: string, speakerId: number, speed: number): Promise<string>` | Generates speech and returns the path of the WAV file. |
| **generateAndPlay** | `(text: string, speakerId: number, speed: number): Promise<void>` | Generates speech and streams it to the device speaker. |
| **stopPlaying** | `(): void` | Immediately stops playback. |
| **addVolumeListener** | `(cb: (volume: number) => void): EmitterSubscription` | Subscribes to real‑time RMS volume callbacks during playback. Call `subscription.remove()` to unsubscribe. |
| **deinitialize** | `(): void` | Frees native resources – call this when your app unmounts or goes to background for a long time. |
| **initSTT** | `(configJson: string): void` | Initialise offline speech recognition with model paths. |
| **startRecognition** | `(): void` | Begin feeding audio samples for STT. |
| **feedAudio** | `(base64Pcm: string): void` | Supply PCM16LE data to the recogniser. |
| **stopRecognition** | `(): Promise<string>` | Finish decoding and return the recognised text. |
| **deinitializeSTT** | `(): void` | Release STT resources. |

### STT Quick Example

```tsx
import TTSManager from 'react-native-sherpa-onnx-offline-tts';
import RNFS from 'react-native-fs';

const cfg = JSON.stringify({
  encoder: '/path/encoder.onnx',
  decoder: '/path/decoder.onnx',
  joiner: '/path/joiner.onnx',
  tokens: '/path/tokens.txt',
});

async function recognise(path: string) {
  await TTSManager.initSTT(cfg);
  TTSManager.startRecognition();
  const data = await RNFS.readFile(path, 'base64');
  TTSManager.feedAudio(data);
  const text = await TTSManager.stopRecognition();
  console.log('Transcription:', text);
}
```

---

## 🔊 Supported Models

* Any **Piper** VITS model (`*.onnx`) with matching `tokens.txt` and `espeak-ng-data` directory.
* Multi‑speaker models are supported – just pass the desired `speakerId`.

> Need other formats? Feel free to open an issue or pull request.

---

## 🛠️ Example App

A minimal, production‑ready example (downloads the model on first launch, shows a progress spinner, animates to mic volume, etc.) lives in **`example/App.tsx`** – the snippet below is an abridged version:

```tsx title="example/App.tsx"
const App = () => {
  /* full source lives in the repo */
  return (
    <View style={styles.container}>
      {isDownloading ? (
        <ProgressBar progress={downloadProgress} />
      ) : (
        <>
          <AnimatedCircle scale={volume} />
          <Button title="Play" onPress={handlePlay} disabled={isPlaying} />
          <Button title="Stop" onPress={handleStop} disabled={!isPlaying} />
        </>
      )}
    </View>
  );
};
```

---

## 🤝 Contributing

Bug reports and PRs are welcome!  Please see [CONTRIBUTING.md](CONTRIBUTING.md) for the full development workflow.

---

## 📄 License

[MIT](LICENSE)

---

Made with ❤️ & [create‑react‑native‑library](https://github.com/callstack/react-native-builder-bob)

