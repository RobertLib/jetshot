# Game Center Integrace - Návod pro App Store Connect

## 📋 Přehled

Tento dokument obsahuje všechny potřebné informace pro nastavení Game Center v App Store Connect pro hru **Jetshot**.

---

## 🎮 Aktivace Game Center

1. Přihlaste se do [App Store Connect](https://appstoreconnect.apple.com)
2. Vyberte vaši aplikaci **Jetshot**
3. Přejděte do sekce **Services** → **Game Center**
4. Klikněte na **Enable Game Center**

---

## 🏆 Leaderboards (Žebříčky)

Vytvořte následující leaderboardy v App Store Connect:

### 1. Total Score

- **Leaderboard ID:** `com.robertlib.jetshot.totalscore`
- **Reference Name:** Total Score
- **Localization (Czech):**
  - Title: "Celkové skóre"
  - Format: Integer
  - Sort Order: High to Low
  - Score Range: 0 - 999999999

### 2. Level 1 High Score

- **Leaderboard ID:** `com.robertlib.jetshot.level1`
- **Reference Name:** Level 1 High Score
- **Localization (Czech):**
  - Title: "Level 1"
  - Format: Integer
  - Sort Order: High to Low

### 3. Level 2 High Score

- **Leaderboard ID:** `com.robertlib.jetshot.level2`
- **Reference Name:** Level 2 High Score
- **Localization (Czech):**
  - Title: "Level 2"
  - Format: Integer
  - Sort Order: High to Low

### 4. Level 3 High Score

- **Leaderboard ID:** `com.robertlib.jetshot.level3`
- **Reference Name:** Level 3 High Score
- **Localization (Czech):**
  - Title: "Level 3"
  - Format: Integer
  - Sort Order: High to Low

### 5. Level 4 High Score

- **Leaderboard ID:** `com.robertlib.jetshot.level4`
- **Reference Name:** Level 4 High Score
- **Localization (Czech):**
  - Title: "Level 4"
  - Format: Integer
  - Sort Order: High to Low

### 6. Level 5 High Score

- **Leaderboard ID:** `com.robertlib.jetshot.level5`
- **Reference Name:** Level 5 High Score
- **Localization (Czech):**
  - Title: "Level 5"
  - Format: Integer
  - Sort Order: High to Low

### 7. Level 6 High Score

- **Leaderboard ID:** `com.robertlib.jetshot.level6`
- **Reference Name:** Level 6 High Score
- **Localization (Czech):**
  - Title: "Level 6"
  - Format: Integer
  - Sort Order: High to Low

### 8. Level 7 High Score

- **Leaderboard ID:** `com.robertlib.jetshot.level7`
- **Reference Name:** Level 7 High Score
- **Localization (Czech):**
  - Title: "Level 7"
  - Format: Integer
  - Sort Order: High to Low

### 9. Level 8 High Score

- **Leaderboard ID:** `com.robertlib.jetshot.level8`
- **Reference Name:** Level 8 High Score
- **Localization (Czech):**
  - Title: "Level 8"
  - Format: Integer
  - Sort Order: High to Low

### 10. Total Coins

- **Leaderboard ID:** `com.robertlib.jetshot.totalcoins`
- **Reference Name:** Total Coins Collected
- **Localization (Czech):**
  - Title: "Sebrané coiny"
  - Format: Integer
  - Sort Order: High to Low

---

## 🎖️ Achievements (Achievementy)

Vytvořte následující achievementy v App Store Connect:

### Kategorie: První kroky

#### 1. First Flight

- **Achievement ID:** `com.robertlib.jetshot.firstflight`
- **Reference Name:** First Flight
- **Points:** 5
- **Hidden:** No
- **Localization (Czech):**
  - Title: "První let"
  - Pre-earned Description: "Dokončete Level 1"
  - Earned Description: "Dokončil jsi Level 1!"

#### 2. Survivor - Level 1

- **Achievement ID:** `com.robertlib.jetshot.survivor.level1`
- **Reference Name:** Survivor Level 1
- **Points:** 10
- **Hidden:** No
- **Localization (Czech):**
  - Title: "Přeživší"
  - Pre-earned Description: "Dokončete Level 1 bez ztráty života"
  - Earned Description: "Dokončil jsi Level 1 bez ztráty života!"

---

### Kategorie: Progres

#### 3. Level 3 Complete

- **Achievement ID:** `com.robertlib.jetshot.completed.level3`
- **Reference Name:** Level 3 Complete
- **Points:** 10
- **Hidden:** No
- **Localization (Czech):**
  - Title: "Pokročilý pilot"
  - Pre-earned Description: "Dokončete Level 3"
  - Earned Description: "Dokončil jsi Level 3!"

#### 4. Level 5 Complete

- **Achievement ID:** `com.robertlib.jetshot.completed.level5`
- **Reference Name:** Level 5 Complete
- **Points:** 15
- **Hidden:** No
- **Localization (Czech):**
  - Title: "Veterán"
  - Pre-earned Description: "Dokončete Level 5"
  - Earned Description: "Dokončil jsi Level 5!"

#### 5. Level 8 Complete

- **Achievement ID:** `com.robertlib.jetshot.completed.level8`
- **Reference Name:** Level 8 Complete
- **Points:** 20
- **Hidden:** No
- **Localization (Czech):**
  - Title: "Mistr vesmíru"
  - Pre-earned Description: "Dokončete Level 8"
  - Earned Description: "Dokončil jsi Level 8!"

#### 6. Level Master

- **Achievement ID:** `com.robertlib.jetshot.levelmaster`
- **Reference Name:** Level Master
- **Points:** 50
- **Hidden:** No
- **Localization (Czech):**
  - Title: "Velmistr"
  - Pre-earned Description: "Dokončete všech 8 levelů"
  - Earned Description: "Dokončil jsi všech 8 levelů!"

---

### Kategorie: Coiny

#### 7. Coin Collector - 100

- **Achievement ID:** `com.robertlib.jetshot.coins100`
- **Reference Name:** Coin Collector 100
- **Points:** 5
- **Hidden:** No
- **Localization (Czech):**
  - Title: "Sběratel mincí"
  - Pre-earned Description: "Seberte 100 coinů"
  - Earned Description: "Sebral jsi 100 coinů!"

#### 8. Coin Collector - 500

- **Achievement ID:** `com.robertlib.jetshot.coins500`
- **Reference Name:** Coin Collector 500
- **Points:** 15
- **Hidden:** No
- **Localization (Czech):**
  - Title: "Zlatokop"
  - Pre-earned Description: "Seberte 500 coinů"
  - Earned Description: "Sebral jsi 500 coinů!"

#### 9. Coin Collector - 1000

- **Achievement ID:** `com.robertlib.jetshot.coins1000`
- **Reference Name:** Coin Collector 1000
- **Points:** 25
- **Hidden:** No
- **Localization (Czech):**
  - Title: "Boháč"
  - Pre-earned Description: "Seberte 1000 coinů"
  - Earned Description: "Sebral jsi 1000 coinů!"

---

### Kategorie: Boj

#### 10. Sharpshooter - 100

- **Achievement ID:** `com.robertlib.jetshot.enemies100`
- **Reference Name:** Sharpshooter 100
- **Points:** 10
- **Hidden:** No
- **Localization (Czech):**
  - Title: "Ostrostřelec"
  - Pre-earned Description: "Zničte 100 nepřátel"
  - Earned Description: "Zničil jsi 100 nepřátel!"

#### 11. Sharpshooter - 500

- **Achievement ID:** `com.robertlib.jetshot.enemies500`
- **Reference Name:** Sharpshooter 500
- **Points:** 20
- **Hidden:** No
- **Localization (Czech):**
  - Title: "Válečník"
  - Pre-earned Description: "Zničte 500 nepřátel"
  - Earned Description: "Zničil jsi 500 nepřátel!"

#### 12. Destroyer - 1000

- **Achievement ID:** `com.robertlib.jetshot.enemies1000`
- **Reference Name:** Destroyer 1000
- **Points:** 30
- **Hidden:** No
- **Localization (Czech):**
  - Title: "Ničitel"
  - Pre-earned Description: "Zničte 1000 nepřátel"
  - Earned Description: "Zničil jsi 1000 nepřátel!"

---

### Kategorie: Boss

#### 13. Boss Slayer

- **Achievement ID:** `com.robertlib.jetshot.firstboss`
- **Reference Name:** Boss Slayer
- **Points:** 15
- **Hidden:** No
- **Localization (Czech):**
  - Title: "Zabiják bossů"
  - Pre-earned Description: "Porazte prvního bosse"
  - Earned Description: "Porazil jsi prvního bosse!"

#### 14. Ultimate Champion

- **Achievement ID:** `com.robertlib.jetshot.allbosses`
- **Reference Name:** Ultimate Champion
- **Points:** 50
- **Hidden:** No
- **Localization (Czech):**
  - Title: "Největší šampion"
  - Pre-earned Description: "Porazte všechny bossy"
  - Earned Description: "Porazil jsi všechny bossy!"

---

### Kategorie: Dokonalost

#### 15. Perfect Run

- **Achievement ID:** `com.robertlib.jetshot.perfectrun`
- **Reference Name:** Perfect Run
- **Points:** 25
- **Hidden:** Yes
- **Localization (Czech):**
  - Title: "Dokonalý běh"
  - Pre-earned Description: "Dosáhněte maximálního skóre na levelu"
  - Earned Description: "Dosáhl jsi maximálního skóre!"

#### 16. Untouchable

- **Achievement ID:** `com.robertlib.jetshot.untouchable3`
- **Reference Name:** Untouchable
- **Points:** 30
- **Hidden:** No
- **Localization (Czech):**
  - Title: "Nedotknutelný"
  - Pre-earned Description: "Dokončete 3 levely bez ztráty života"
  - Earned Description: "Dokončil jsi 3 levely bez ztráty života!"

---

### Kategorie: Power-upy

#### 17. Power-Up Master

- **Achievement ID:** `com.robertlib.jetshot.powerupmaster`
- **Reference Name:** Power-Up Master
- **Points:** 10
- **Hidden:** No
- **Localization (Czech):**
  - Title: "Mistr power-upů"
  - Pre-earned Description: "Použijte všechny typy power-upů"
  - Earned Description: "Použil jsi všechny typy power-upů!"

---

## 🔧 Nastavení v Xcode

### Přidání Game Center Capability

1. Otevřete projekt v Xcode
2. Vyberte projekt v Project Navigator
3. Vyberte Target **jetshot**
4. Přejděte na záložku **Signing & Capabilities**
5. Klikněte na **+ Capability**
6. Vyhledejte a přidejte **Game Center**

### Info.plist

Ujistěte se, že máte v Info.plist:

```xml
<key>UIRequiredDeviceCapabilities</key>
<array>
    <string>gamekit</string>
</array>
```

---

## 🧪 Testování

### Sandbox Testing

1. V App Store Connect vytvořte **Sandbox Tester** účet
2. Na iOS zařízení:
   - Odhlaste se z Game Center
   - Spusťte aplikaci
   - Při výzvě k přihlášení použijte Sandbox účet

### Testování Leaderboards

```swift
// V kódu můžete volat:
GameCenterManager.shared.submitScore(1000, to: GameCenterManager.LeaderboardID.level1)
```

### Testování Achievements

```swift
// V kódu můžete volat:
GameCenterManager.shared.reportAchievement(GameCenterManager.AchievementID.firstFlight)
```

### Reset dat (pouze pro testování!)

```swift
// Reset achievementů
GameCenterManager.shared.resetAchievements()

// Reset lokálního trackingu
GameCenterManager.shared.resetLocalTracking()

// Reset progrese levelů
LevelManager.shared.resetProgress()
```

---

## 📊 Statistiky

**Celkem Leaderboards:** 10
**Celkem Achievements:** 17
**Celkový počet bodů:** 405

---

## 🎯 Implementované funkce

✅ Automatické odesílání skóre po dokončení levelu
✅ Tracking coinů v reálném čase
✅ Tracking zničených nepřátel
✅ Tracking poražených bossů
✅ Tracking použitých power-upů
✅ Detekce dokonalého dokončení (bez ztráty života)
✅ Tlačítko v menu pro přístup k Game Center
✅ Automatická autentikace při startu aplikace

---

## 📝 Poznámky

- Všechna ID jsou ve formátu reverse domain notation
- Achievementy jsou přírůstkové - trackují se automaticky
- "Perfect Run" achievement je skrytý (hidden) - překvapení pro hráče
- Leaderboardy mají neomezený rozsah skóre
- Sandbox testing je nezbytný před publikováním

---

## 🚀 Příští kroky

1. **Vytvořte všechny leaderboardy v App Store Connect**
2. **Vytvořte všechny achievementy v App Store Connect**
3. **Přidejte Game Center capability v Xcode**
4. **Otestujte se Sandbox účtem**
5. **Nahrajte build do TestFlight**
6. **Beta testování s reálnými hráči**
7. **Publikování na App Store**

---

## ⚠️ Důležité upozornění

**Bundle ID musí odpovídat!**
Zkontrolujte, že Bundle ID v Xcode projektu odpovídá Bundle ID aplikace v App Store Connect.

Pokud je váš Bundle ID jiný než `com.robertlib.jetshot`, upravte všechna ID v `GameCenterManager.swift`:

- Nahraďte `com.robertlib.jetshot` za váš skutečný Bundle ID
- Například: `com.vaseJmeno.jetshot.totalscore`

---

**Připraveno pro implementaci! 🎮✨**
