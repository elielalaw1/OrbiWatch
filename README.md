# Orbi for Apple Watch

## Installera via din iPhone

Du behöver en Mac med Xcode som stöder dina enheters systemversioner, en iPhone med iOS 17 eller senare och en parkopplad Apple Watch med watchOS 10 eller senare.

1. Hämta repot via **Code → Download ZIP** och packa upp det. Öppna **OrbiPhoneCompanion/Orbi.xcodeproj**.
2. Lägg till ditt Apple-konto i Xcodes inställningar. Markera det blå projektet och välj **Project → Orbi → Build Settings → All**. Sök efter **ORBI_PHONE_ID** och ange ett unikt id, exempelvis `se.dittnamn.orbi`, för både Debug och Release. Klockans id och kopplingen mellan apparna följer automatiskt.
3. Under **Targets** väljer du först **OrbiPhone** och sedan **Orbi**. Under **Signing & Capabilities** för varje target, välj ditt eget **Team** och aktivera automatisk signering.
4. Anslut din iPhone till datorn och godkänn parkoppling och utvecklarläge på enheterna om Xcode ber om det. Välj schemat **OrbiPhone**, välj din iPhone och tryck **⌘R**.
5. Öppna appen **Watch** på iPhone. Om Orbi visas under **Tillgängliga appar**, tryck **Installera**. Öppna Orbi på klockan och ge mikrofonåtkomst.

För den separata watchOS-appen finns Xcode-instruktioner nedan. Det alternativa skriptet i `Tools/install_watch.py` kräver Python med `pymobiledevice3`, en redan betrodd parkoppling och en watchOS-app signerad för just din klocka. Kör med `--help` för argumenten.

For the iPhone app that embeds Orbi for Apple Watch, open **[OrbiPhoneCompanion/Orbi.xcodeproj](OrbiPhoneCompanion/Orbi.xcodeproj)** and select the **OrbiPhone** scheme. This companion variant is experimental. The physical Watch installation was verified with the standalone project described below.

A native English-language app for Apple Watch SE (2nd generation), watchOS 10 or later.

The display is Orbi's entire face. It adapts the latest local Wisdome version at commit `8406510`: the 1.15-unit pixel sampling grid, large light eyes, pupils, glints, eyebrows and curved mouth. The dome projection is mapped to a flat watch screen. The sleep, wake and SHHH poses extend that character for this app.

## Sound-driven story

- **Sleeping.** An almost black surface, faint closed eyes, a subtly breathing mouth and drifting Zs. Normal quiet-room sound keeps him asleep.
- **Stirring.** Moderate sound slowly opens his eyes and brightens the full screen. If the sound subsides, he settles back down.
- **Angry.** Three sustained seconds above the sound limit wake him fully. The whole screen turns red. His brows tilt, his mouth opens with teeth and tongue, and he says “Hey! I'm trying to sleep!”
- **SHHH.** He raises a finger and says “Silence! Please keep it down!”
- **Back to sleep.** He says “I'm going back to sleep. Good night.” The surface dims, his eyes close, and the Zs return. A ten-second cooldown gives him time to settle.

The microphone is paused during his own speech, so Orbi cannot trigger himself. Audio is processed in memory and never saved or uploaded. The sound limit is a relative microphone level, not calibrated environmental decibels.

Dialogue is spoken without on-screen captions or bubbles. The main face hides the system clock using SwiftUI's underscored `_statusBarHidden` modifier, verified in the installed simulator SDK. This API should be revisited before distribution.

Long-press the face to open **Quiet settings**. Adjust the limit, turn speech on or off, pause or resume listening, or run **Preview story**. The preview feeds increasing synthetic levels into the same wake logic as the microphone.

Listening starts when the app opens, after microphone permission. This version runs in the foreground and pauses when watchOS backgrounds the app. The dark sleep graphics do not switch off the physical display or override the watch's power management. Keep the app open for the installation. Real microphone sensitivity and speaker loudness need tuning on the physical watch.

## Open the project

Open **Orbi.xcodeproj** in Xcode. Select the **Orbi** scheme.

## Run the simulator

Select a 40 mm Apple Watch simulator as the run destination and press **Command-R**. In Xcode 27, use **Xcode → Open Developer Tool → Device Hub** to see the running watch. If prompted to download the watchOS simulator runtime, install it in Xcode's Components settings.

The local preview uses a 40 mm SE 3 simulator because the installed watchOS 27.2 runtime cannot create an SE 2 device. Physical SE 2 support is targeted at watchOS 10 and later. The physical device's installed watchOS version must also be supported by your Xcode installation.

## Install on your Apple Watch

1. Keep your Apple Watch paired with your iPhone, nearby and unlocked. Connect the iPhone to your Mac and accept Trust if asked. Enable Wi-Fi and Bluetooth.
2. In Xcode, open **Settings → Accounts** and add your Apple Account. Complete sign-in yourself.
3. Open **Device Hub** using **Xcode → Open Developer Tool → Device Hub**. Pair the iPhone for development and wait for its Apple Watch to become available.
4. Enable **Developer Mode** on both the iPhone and watch in **Settings → Privacy & Security → Developer Mode**. Follow the restart and confirmation prompts. The option may appear only after Xcode starts pairing the devices.
5. In the project navigator, select the blue **Orbi** project, select the **Orbi** target, then **Signing & Capabilities**. Keep automatic signing enabled and select your Personal Team. If Xcode says the bundle identifier is already in use, change `com.eli.orbi.quietwatch` to a unique identifier of your own.
6. Choose your actual Apple Watch as the run destination and press **Command-R**. Wait for installation to finish. Open Orbi on the watch and allow microphone access. Long-press the face for settings.

A free Personal Team can be used for personal-device testing, with Apple's provisioning limits. Free profiles expire after seven days and need installation again from Xcode. App Store distribution requires Apple Developer Program membership.

References: [Apple device pairing](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac), [developer accounts and Personal Teams](https://developer.apple.com/help/account/basics/about-your-developer-account/).

## Validation

The project builds for watchOS Simulator and generic watchOS hardware with signing disabled. Deterministic tests exercise the actual sound-state implementation for quiet input, gradual waking, transient rejection, sleep recovery, sustained loud input, cooldown and re-arming. Simulator previews check the visual story. Real microphone sensitivity, speech, haptics, battery use and physical SE 2 installation still need on-device verification.
