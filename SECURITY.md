# Security Policy

VPS Control şəxsi serverə management girişi verdiyi üçün security boundary məhsul funksiyasının bir hissəsidir.

## Supported state

Layihə hazırda paused local MVP-dir. Ubuntu Server 24.04 LTS ilə public-key SSH yolu yoxlanılıb. Başqa OS və Ubuntu release-ləri Compatibility Check və live test matrisi tamamlanana qədər supported hesab edilmir.

## Vulnerability reporting

Security problemi aşkar etdikdə secret, private key, real IP, username, terminal output və exploit detallarını public GitHub issue-da paylaşmayın. GitHub Private Vulnerability Reporting aktivdirsə ondan istifadə edin; əks halda repository owner ilə private kanal vasitəsilə əlaqə saxlayın.

Report daxilində yalnız təhlükəsiz reproduksiya addımlarını, təsiri, təsirlənən versiyanı və mümkün remediation-u verin. Real credential əvəzinə synthetic test data istifadə edin.

## Repository hygiene

Heç vaxt repozitoriyaya bunları əlavə etməyin:

- SSH private key-ləri, sudo password-ları və API token-ləri
- `.env` və local configuration faylları
- real VPS IP/hostname, private infrastructure məlumatı və unredacted screenshot-lar
- terminal recording, raw command history və credential olan loglar
- signing certificate, provisioning profile və export edilmiş Keychain materialı

Commit-dən əvvəl staged faylları və diff-i ayrıca yoxlayın. `.gitignore` təhlükəsizlik yoxlamasının əvəzi deyil.

`QA/` lokal olaraq saxlanır və Git-dən kənardadır: terminal screenshot-larında host maskalansa belə client IP kimi session metadata görünə bilər.

## Product security invariants

- Root və password-based SSH aktiv edilməməlidir.
- `StrictHostKeyChecking` söndürülməməlidir.
- Public admin UI və ya Docker API portu açılmamalıdır.
- Portainer gələcəkdə əlavə edilərsə VPS loopback interface-də işləməli və yalnız SSH tunnel vasitəsilə açılmalıdır.
- Monitorinq default olaraq read-only qalmalıdır.
- Privileged və destructive əməliyyat target, effect və risk preview-dan sonra ayrıca təsdiq tələb etməlidir.
- Private key məzmunu tətbiq yaddaşına və persistence-a import edilməməlidir.
- Gələcək AI Chat arbitrary shell command icra etməməli, secret göndərməməli və user approval olmadan remote state dəyişməməlidir.
