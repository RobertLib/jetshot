# 🎮 Game Center - Rychlý start

## ✅ Co bylo implementováno

Kompletní Game Center integrace pro vaši hru Jetshot je připravena!

### 📁 Nové soubory

- `GameCenterManager.swift` - Hlavní manager pro Game Center
- `GAME_CENTER_SETUP.md` - Detailní dokumentace pro App Store Connect

### 🔧 Upravené soubory

- `AppDelegate.swift` - Autentikace při startu
- `LevelManager.swift` - Odesílání skóre
- `GameScene.swift` - Tracking achievementů během hry
- `MenuScene.swift` - Tlačítko Game Center

---

## 🚀 Co nyní udělat?

### 1. Přidejte Game Center Capability v Xcode

1. V Xcode otevřete projekt
2. Vyberte Target → **jetshot**
3. Záložka **Signing & Capabilities**
4. Klikněte **+ Capability**
5. Přidejte **Game Center**

### 2. Zkontrolujte Bundle ID

Bundle ID musí odpovídat tomu v App Store Connect.

**Pokud máte jiný Bundle ID než `com.robertlib.jetshot`:**

Upravte všechna ID v souboru `GameCenterManager.swift` (řádky 20-76):

```swift
struct LeaderboardID {
    static let totalScore = "com.VASE_ID.jetshot.totalscore"
    // ... atd
}
```

### 3. Vytvořte leaderboardy a achievementy

Přejděte do App Store Connect a vytvořte všechny položky podle návodu v `GAME_CENTER_SETUP.md`.

**Celkem:**

- 10 leaderboardů
- 17 achievementů

### 4. Testování

Pro testování budete potřebovat:

- ✅ Apple Developer účet
- ✅ Sandbox Tester účet (vytvoříte v App Store Connect)
- ✅ Reálné iOS zařízení (nebo simulátor s Game Center)

---

## 🎯 Jak to funguje

### Automatický tracking

Vše funguje automaticky:

✅ **Skóre** - odesílá se automaticky po dokončení levelu
✅ **Coiny** - trackují se při sběru
✅ **Nepřátelé** - trackují se při zničení
✅ **Bossové** - trackují se při porážce
✅ **Power-upy** - trackují se při použití
✅ **Dokonalé běhy** - detekují se automaticky

### UI v menu

V hlavním menu je tlačítko **"GAME CENTER"** které otevře:

- Leaderboardy (žebříčky)
- Achievementy
- Přihlášení do Game Center (pokud není přihlášen)

---

## 🧪 Debug režim

Pro testování můžete použít:

```swift
// Zobrazit všechny achievementy
GameCenterManager.shared.showAchievements(from: viewController)

// Zobrazit konkrétní leaderboard
GameCenterManager.shared.showLeaderboard(
    from: viewController,
    leaderboardID: GameCenterManager.LeaderboardID.level1
)

// Ručně odeslat skóre (pro testování)
GameCenterManager.shared.submitScore(9999, to: GameCenterManager.LeaderboardID.totalScore)

// Ručně odemknout achievement (pro testování)
GameCenterManager.shared.reportAchievement(GameCenterManager.AchievementID.firstFlight)
```

### Reset dat (pouze pro testování!)

```swift
// Reset všech achievementů v Game Center
GameCenterManager.shared.resetAchievements()

// Reset lokálního trackingu (coiny, nepřátelé, atd.)
GameCenterManager.shared.resetLocalTracking()

// Reset progrese levelů
LevelManager.shared.resetProgress()
```

---

## 📊 Leaderboardy

### Hlavní žebříčky

- **Total Score** - součet skóre ze všech levelů
- **Total Coins** - celkový počet sebraných coinů

### Level žebříčky

- **Level 1-8** - nejlepší skóre pro každý level

---

## 🏆 Achievementy

### 17 achievementů v kategoriích:

**První kroky** (2)

- First Flight - dokončit level 1
- Survivor - dokončit level 1 bez poškození

**Progres** (4)

- Dokončit level 3, 5, 8
- Level Master - dokončit všech 8 levelů

**Coiny** (3)

- Sebrat 100, 500, 1000 coinů

**Boj** (3)

- Zničit 100, 500, 1000 nepřátel

**Boss** (2)

- Porazit prvního bosse
- Ultimate Champion - porazit všechny bossy

**Dokonalost** (2)

- Perfect Run - maximální skóre (skrytý)
- Untouchable - 3 levely bez poškození

**Power-upy** (1)

- Power-Up Master - použít všechny typy

---

## ⚡ Výhody pro vaši hru

✨ **Větší zapojení hráčů** - leaderboardy motivují k opakování
✨ **Sociální prvek** - soutěž s přáteli
✨ **Profesionalita** - standardní funkce iOS her
✨ **Žádné extra náklady** - součást Apple ekosystému
✨ **Zvýšená retention** - achievementy udržují hráče

---

## 📱 Testování na zařízení

1. **Odhlaste se** z Game Center (Nastavení → Game Center)
2. **Spusťte hru** na zařízení
3. Zobrazí se přihlášení - použijte **Sandbox účet**
4. **Hrajte hru** - data se odesílají automaticky
5. **Zkontrolujte** v Game Center aplikaci

---

## ❓ Časté problémy

### "Player not authenticated"

➡️ Hráč musí být přihlášen do Game Center

### "Failed to submit score"

➡️ Zkontrolujte, že leaderboard ID existuje v App Store Connect

### "Cannot show leaderboard"

➡️ Zkontrolujte internetové připojení a autentikaci

### Achievementy se neodemykají

➡️ Zkontrolujte, že achievement ID existuje v App Store Connect

---

## 📖 Další dokumentace

Pro kompletní návod a všechna ID viz: **`GAME_CENTER_SETUP.md`**

---

**Hotovo! Vaše hra je připravena na Game Center integr! 🎉**
