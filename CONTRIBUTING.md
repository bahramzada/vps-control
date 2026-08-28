# Contributing

VPS Control hazırda development pause vəziyyətindədir. Dəyişiklik etməzdən əvvəl `AGENTS.md`, `about_project.md`, `ROADMAP.md` və uyğun source/test fayllarını oxuyun.

## Development setup

Tələblər: macOS 14+, Swift 6.2 və sistem OpenSSH.

```sh
swift build
swift test
```

Release packaging-i yoxlamaq üçün:

```sh
Scripts/package-app.sh release
```

## Change rules

- Dəyişiklikləri mövcud native SwiftUI/AppKit arxitekturasında saxlayın.
- Yeni production dependency, public listener, VPS mutation və root-equivalent giriş əvvəlcədən security review və açıq approval tələb edir.
- Remote command-ları typed, fixed və test edilən boundary daxilində saxlayın; user input-u shell string-ə concatenate etməyin.
- Read-only və mutating funksiyaları UI-da və kodda aydın ayırın.
- Private key, password, token, real host/IP, şəxsi local path və terminal content əlavə etməyin.
- Yeni behavior üçün ən dar uyğun testləri, security-sensitive dəyişiklik üçün isə failure və cancel-path testlərini əlavə edin.
- Verified fakt dəyişəndə `about_project.md` və `ROADMAP.md` fayllarını yeniləyin; tamamlanmış write-task üçün `progress.md`-ə entry əlavə edin.

## Pull request checklist

- [ ] Scope yalnız təsvir edilən dəyişikliklə məhduddur.
- [ ] Secret və private infrastructure scan edilib.
- [ ] `swift test` uğurla tamamlanıb.
- [ ] UI dəyişibsə accessibility və keyboard behavior yoxlanılıb.
- [ ] Remote state dəyişən əməliyyatlarda target/effect/risk preview və explicit confirmation var.
- [ ] Uyğun documentation yenilənib.
