# Rychlá příručka - Přidání CloudStorageManager.swift do Xcode projektu

## Důležité!

Nový soubor `CloudStorageManager.swift` byl vytvořen, ale musíte ho ještě **přidat do Xcode projektu**.

## Kroky:

### 1. Přidání souboru do projektu

1. Otevřete Xcode a projekt `jetshot.xcodeproj`
2. V **Project Navigator** (levý panel) klikněte pravým tlačítkem na složku `jetshot` (žlutá složka s ikonou aplikace)
3. Vyberte **Add Files to "jetshot"...**
4. V dialogu najděte soubor `CloudStorageManager.swift` (měl by být ve složce `jetshot/`)
5. Ujistěte se, že je zaškrtnuto:
   - ☑️ **Copy items if needed**
   - ☑️ **jetshot** target
6. Klikněte na **Add**

### 2. Ověření

- V **Project Navigator** byste měli vidět `CloudStorageManager.swift` mezi ostatními Swift soubory
- Soubor by měl být ve složce `jetshot/` společně s ostatními `.swift` soubory

### 3. Build

- Stiskněte **⌘B** (Command + B) pro build
- Mělo by proběhnout bez chyb

---

**Nebo** můžete použít drag & drop:

1. V **Finder** najděte soubor `CloudStorageManager.swift`
2. Přetáhněte ho do **Project Navigator** v Xcode (do žluté složky `jetshot`)
3. V dialogu zaškrtněte **Copy items if needed** a target **jetshot**
4. Klikněte **Finish**

---

## Co dál?

Po přidání souboru do projektu pokračujte podle `ICLOUD_SETUP.md` pro nastavení iCloud capability.
