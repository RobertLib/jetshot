# iCloud Setup - Instrukce pro nastavení

## Přehled

Aplikace nyní používá **iCloud Key-Value Storage** pro synchronizaci herního postupu mezi zařízeními a zachování dat po přeinstalování aplikace.

## Co se ukládá do iCloudu

- ✅ Dokončené levely (`completedLevels`)
- ✅ Skóre jednotlivých levelů (`levelScores`)
- ✅ Celkový počet sebraných mincí (`totalCoins`)
- ✅ Celkový počet zničených nepřátel (`totalEnemies`)
- ✅ Počet levelů bez poškození (`levelsWithoutDamage`)
- ✅ Počet poražených bossů (`bossesDefeated`)
- ✅ Použité typy power-upů (`powerUpTypesUsed`)

## Kroky pro nastavení iCloud v Xcode

### 1. Přihlášení k Apple Developer účtu

- V Xcode otevřete **Preferences** (⌘,)
- Přejděte na **Accounts**
- Přidejte svůj Apple Developer účet (pokud tam ještě není)

### 2. Nastavení Bundle Identifier

- V Xcode otevřete projekt `jetshot.xcodeproj`
- Vyberte target **jetshot**
- V záložce **Signing & Capabilities**:
  - Zkontrolujte, že máte správný **Bundle Identifier** (např. `com.robertlib.jetshot`)
  - Vyberte svůj **Team** (Apple Developer účet)
  - Zapněte **Automatically manage signing** (pokud není již zapnuto)

### 3. Přidání iCloud Capability

1. V záložce **Signing & Capabilities** klikněte na **+ Capability** (vlevo nahoře)
2. Najděte a přidejte **iCloud**
3. V nové sekci **iCloud** zaškrtněte:
   - ☑️ **Key-value storage**
   - (Ostatní možnosti jako CloudKit nebo iCloud Documents NEZAŠKRTÁVEJTE)

### 4. Nastavení App ID v App Store Connect (pokud ještě neexistuje)

1. Přihlaste se na [App Store Connect](https://appstoreconnect.apple.com)
2. Jděte na **Identifiers** → **App IDs**
3. Najděte nebo vytvořte App ID pro `com.robertlib.jetshot`
4. Ujistěte se, že **iCloud** je zapnutý v **Capabilities**

### 5. Testování

#### Testování na simulátoru:

1. Otevřete **Simulator**
2. V menu vyberte **Features** → **iCloud** → **Sign In**
3. Přihlaste se svým Apple ID (testovacím)

#### Testování na reálném zařízení:

1. Na iOS zařízení jděte do **Settings** → **[Your Name]** → **iCloud**
2. Ujistěte se, že jste přihlášeni k iCloud
3. Zkontrolujte, že **iCloud Drive** je zapnutý

#### Test funkcionality:

1. Spusťte hru a dokončete pár levelů
2. Smažte aplikaci z telefonu/simulátoru
3. Nainstalujte a spusťte znovu
4. ✅ Váš postup by měl být zachován!

#### Test synchronizace mezi zařízeními:

1. Nainstalujte aplikaci na 2 iOS zařízení se stejným Apple ID
2. Dokončete level na zařízení 1
3. Zavřete a znovu otevřete aplikaci na zařízení 2
4. ✅ Postup by se měl synchronizovat

### 6. Debug (pokud něco nefunguje)

Do kódu přidejte debug výpis v `AppDelegate.swift`:

```swift
// V applicationDidFinishLaunching nebo po inicializaci
CloudStorageManager.shared.printCloudStatus()
```

Zkontrolujte v konzoli:

- Je iCloud dostupný? (`Available: true`)
- Načítají se data z iCloudu?

## Limity iCloud Key-Value Storage

- **Maximální velikost:** 1 MB celkem pro všechna data
- **Maximální počet klíčů:** 1024
- **Maximální velikost hodnoty:** 1 MB na klíč
- **Synchronizace:** Několik sekund až minut (není okamžitá)

Pro vaši hru je to naprosto dostačující! 🎮

## Poznámky

- Data jsou automaticky zálohována do iCloudu při každé změně
- Synchronizace funguje pouze pro zařízení se stejným Apple ID
- Uživatel musí být přihlášen do iCloudu
- Pokud není iCloud dostupný, aplikace stále funguje (ukládá lokálně)
- Po opětovném připojení k iCloudu se data automaticky synchronizují

## Co dělat, pokud to nefunguje

1. Zkontrolujte, že je v Xcode správně přidána **iCloud Capability**
2. Zkontrolujte, že je na zařízení přihlášen **iCloud účet**
3. Ujistěte se, že máte správný **Bundle Identifier**
4. Zkuste **Clean Build Folder** (⇧⌘K) a znovu buildnout
5. Restartujte Xcode
6. Zkontrolujte v **Apple Developer Console**, že je iCloud zapnutý pro vaše App ID

## Další možnosti (pro budoucnost)

Pokud byste v budoucnu potřebovali ukládat více dat:

- **CloudKit** - pro složitější databázové struktury
- **iCloud Documents** - pro ukládání souborů (např. save game files)
- **Game Center Saved Games** - pro herní save files

Ale pro váš případ je **Key-Value Storage** ideální řešení! ✨
