# x509_flutter

Концепт універсального клієнта для захищеної комунікації на базі протоколів X.509.

## Концепція універсального клієнта

Цей проєкт розробляється як **універсальний кросплатформний клієнт** (macOS, iOS, Android тощо), що повноцінно підтримує роботу з протоколами **v1** та **v2**. 

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

1. **Monobank / Fintech-IT Group**: Основні вакансії банку публікуються на IT-ресурсах на кшталт [Djinni](https://djinni.co/jobs/?query=monobank+flutter) та [LinkedIn](https://www.linkedin.com/jobs/search/?keywords=Monobank%20Flutter), де банк регулярно шукає Flutter-інженерів для розвитку свого супер-додатку.
2. **PrivatBank (ПриватБанк)**: Найбільший банк України постійно публікує вакансії для *Middle/Senior Flutter Developers* на [Work.ua](https://www.work.ua/jobs-flutter-privatbank/) та [robota.ua](https://robota.ua/), де вимагається досвід роботи з архітектурою BLoC, безпечним мережевим шаром та складною UI-логікою.
3. **ПУМБ (PUMB)**: ПУМБ був одним з перших великих банків у світі, який відкрито перевів розробку мобільного додатку на Flutter. Їхні відкриті вакансії для Flutter-розробників часто можна знайти на [офіційному кар'єрному сайті банку](https://career.pumb.ua/ua/it) та порталах як [robota.ua](https://robota.ua/zapros/flutter-pumb).
4. **Ощадбанк та інші**: Хоча Ощадбанк рідше публікує відкриті вакансії напряму через агрегатори, тенденція переходу державних та комерційних банків на Flutter для уніфікації iOS/Android розробки є загальноринковою практикою.

Використання Flutter дозволяє нашому `x509_flutter` клієнту відповідати найвищим стандартам швидкодії та банківської безпеки, маючи при цьому спільну кодову базу для мобільних та десктопних платформ.

---

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
