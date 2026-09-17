# e-learning-aza

Katalog kursus sederhana (in-memory, tanpa database) - dipakai sebagai proyek
demo/test untuk pipeline AI CI/CD (`Jenkinsfile` di repo ini): GitHub Issue
berlabel `ai-task` -> Claude Code CLI implementasi + test -> build/test/
SonarQube/Trivy -> Pull Request ke `main` untuk direview manual.

## Menjalankan secara lokal

```
npm test
```

Tidak ada langkah build - ini murni modul Node (lihat `src/courses.js`) tanpa
bundler/framework, sengaja dibuat minim supaya cepat untuk uji coba pipeline.

## Struktur

- `src/courses.js` - logika katalog kursus & pendaftaran
- `test/courses.test.js` - unit test (Node built-in test runner, `node --test`)
- `Jenkinsfile`, `ci/`, `podman/` - pipeline AI CI/CD, lihat `SETUP.md`
