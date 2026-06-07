# x509_flutter

Концепт універсального клієнта для захищеної комунікації на базі протоколів X.509.

## Концепція універсального клієнта

Цей проєкт розробляється як **універсальний кросплатформний клієнт** (macOS, iOS, Android, Linux, Windows тощо), що повноцінно підтримує роботу з протоколами **v1** та **v2**. 

Офіційна специфікація та документація протоколу: [https://protocol.zencrypted.uk](https://protocol.zencrypted.uk)

Клієнт спроєктований для безперебійної та безпечної взаємодії за допомогою Multicast/Broadcast-повідомлень, ASN.1/DER кодування і строгих стандартів X.509. Гнучка архітектура дозволяє легко масштабувати додаток та підтримувати зворотну сумісність між різними версіями криптографічних протоколів.

## Чому саме Flutter? (Мотивація)

Для розробки універсального клієнта було обрано фреймворк **Flutter**. Головною мотивацією є те, що ця технологія де-факто стала стандартом надійності, продуктивності та безпеки у сфері FinTech та банківського сектору України.

На Flutter уже написані або активно розвиваються додатки найбільших українських банків:

* **Monobank (Universal Bank)**
* **PrivatBank (ПриватБанк)**
* **PUMB (ПУМБ)**
* **Ощадбанк (Oschadbank)**

### Докази затребуваності та використання у банках

Те, що банківський сектор повністю довіряє Flutter, легко підтверджується відкритими вакансіями на популярних рекрутингових платформах (Work.ua, robota.ua, LinkedIn, Djinni, DOU):

1. **Monobank / Fintech-IT Group**: Основні вакансії банку публікуються на IT-ресурсах на кшталт [Djinni](https://djinni.co/jobs/keyword-flutter/) та [LinkedIn](https://www.linkedin.com), де банк регулярно шукає Flutter-інженерів для розвитку свого супер-додатку.
2. **PrivatBank (ПриватБанк)**: Найбільший банк України постійно публікує вакансії для *Middle/Senior Flutter Developers* на [Work.ua](https://www.work.ua/jobs-flutter/) та [robota.ua](https://robota.ua/), де вимагається досвід роботи з архітектурою BLoC, безпечним мережевим шаром та складною UI-логікою.
3. **ПУМБ (PUMB)**: ПУМБ був одним з перших великих банків у світі, який відкрито перевів розробку мобільного додатку на Flutter. Їхні відкриті вакансії для Flutter-розробників часто можна знайти на [офіційному кар'єрному сайті банку](https://career.pumb.ua/ua/it) та порталах як [robota.ua](https://robota.ua/zapros/flutter/ukraine).
4. **Ощадбанк та інші**: Хоча Ощадбанк рідше публікує відкриті вакансії напряму через агрегатори, тенденція переходу державних та комерційних банків на Flutter для уніфікації iOS/Android розробки є загальноринковою практикою.

Використання Flutter дозволяє нашому `x509_flutter` клієнту відповідати найвищим стандартам швидкодії та банківської безпеки, маючи при цьому спільну кодову базу для мобільних та десктопних платформ.

---

## Build Prerequisites

To build `x509_flutter` across different platforms, you need to set up the appropriate development environments:

### macOS & iOS

* **Xcode**: The latest version installed from the Mac App Store.
* **CocoaPods**: Required for resolving iOS/macOS dependencies (`freerasp`, etc.).
  ```bash
  brew install cocoapods
  ```
* *Note: The iOS build requires a physical device for some RASP features, though the app can compile for the simulator.*

### Android

* **Java Development Kit (JDK)**: **Java 17** is the recommended version for compiling the project using Gradle.
  ```bash
  brew install openjdk@21
  export JAVA_HOME=/opt/homebrew/opt/openjdk@21
  ```
* **Android SDK**: Requires Android SDK Platform 36 and Build-Tools 28.0.3. If you do not use Android Studio, you can install them via `sdkmanager`:
  ```bash
  export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
  yes | sdkmanager "platforms;android-36" "build-tools;28.0.3"
  ```

### Linux

To build the Linux desktop application, install the following dependencies (for Debian/Ubuntu-based systems):

```bash
sudo apt-get update
sudo apt-get install -y clang cmake git ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
```

### Windows

To build the Windows desktop application, install **Visual Studio 2022** (not just VS Code) and ensure you include the following workload during installation:

* **Desktop development with C++** (including the MSVC compiler, Windows 10/11 SDK, and C++ CMake tools).

### Build Script

A convenience script is provided to automatically compile obfuscated release builds for Android, iOS, and macOS:

```bash
./scripts/build_release.sh
```
