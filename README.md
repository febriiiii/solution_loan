# README — Aplikasi Pinjaman Online (Digital Lending)
### Solution Design Document (SDD) · PT. XYZ / gaya Livin by Mandiri

> **Loan = Pinjaman.** Proyek ini adalah rancangan sistem **pinjaman online (digital lending)** — nasabah meminjam uang lewat aplikasi mobile, lalu mengembalikannya dengan cicilan + bunga. Dokumen ini menyatukan seluruh rancangan: arsitektur, alur, data, aturan bisnis, dan kepatuhan OJK.

---

## 1. Tentang Proyek

| | |
|---|---|
| **Nama** | Aplikasi Pinjaman Online (Digital Lending) |
| **Domain** | Consumer / Retail Lending — pinjaman perorangan |
| **Kanal** | Mobile app (iOS & Android) untuk nasabah + back-office web untuk petugas |
| **Plafon** | Maksimal Rp12.000.000, tenor maksimal 12 bulan |
| **Konteks** | Test interview Solution Engineer — dirancang setara standar bank BUMN |
| **Tingkat** | High-Level Design (HLD) — lengkap end-to-end, tanpa kode implementasi |

**Apa yang dilakukan sistem ini (singkat):** calon nasabah mendaftar & verifikasi identitas (KYC) → mendapat limit → mengajukan pinjaman → dinilai (credit scoring + SLIK OJK) → bila disetujui, dana dicairkan & jadwal cicilan dibuat → nasabah membayar cicilan → bila menunggak, ada denda/kolektibilitas/restrukturisasi.

---

## 2. Kebutuhan yang Dipenuhi

**A. Kebutuhan inti (dari soal / SSOT):**
1. Registrasi + upload KTP & selfie
2. Login password atau biometric
3. Lihat sisa hutang & tagihan bulanan
4. Pinjam maks Rp12jt, tenor maks 12 bulan
5. Pengajuan diproses → diterima/ditolak
6. Notifikasi email & SMS bila disetujui
7. Tidak boleh pinjam lagi bila masih ada pinjaman berjalan

**B. Kebutuhan enterprise (ditambahkan agar setara bank BUMN):**
- **NoCIF** — identitas nasabah terpisah dari akun login
- **loan_products** — limit/tenor/bunga sebagai konfigurasi (bukan hardcode)
- **SLIK OJK** — cek riwayat kredit sebelum keputusan
- **Akad + tanda tangan digital** sebelum pencairan
- **Kolektibilitas (Kol 1–5)** & Days Past Due (DPD)
- **Restrukturisasi** sesuai OJK (anti-evergreening)
- **Bayar sebagian** (partial payment) dengan waterfall alokasi
- **Maker–checker** (segregation of duties)
- **Audit trail immutable**

---

## 3. Daftar File (Deliverable)

| File | Isi | Untuk apa |
|---|---|---|
| **SDD_PinjamanOnline_v2.docx** | Dokumen desain lengkap (24 hal) dengan diagram tertanam | Deliverable utama — dibaca/di-submit |
| **SDD_PinjamanOnline_v2.pdf** | Versi PDF dari docx | Preview cepat / lampiran |
| **SDD_PinjamanOnline_v2.md** | Sumber markdown dokumen | Bila mau edit teks / copy-paste |
| **schema_v2_sqlserver.sql** | Skema database SQL Server (22 tabel) | Generate database & ERD di dbForge |
| **Diagrams_Editable_v2.zip** | 12 diagram (format `.mmd`, `.drawio`, `.svg`) + panduan | Edit diagram secara gratis |
| **README.md** | File ini | Penjelasan & panduan proyek |

> Catatan: ada juga versi v1 (sederhana, sesuai soal apa adanya). **Pakai v2** — itu versi final yang sudah setara standar bank.

---

## 4. Arsitektur (Ringkas)

Gaya **microservices berlapis** + **Clean Architecture** di tiap service, backend **Python + FastAPI**.

```
Mobile App / Back-office
        │
   API Gateway (routing · auth · rate limit)
        │
   ┌────┴─────────────────────────────────────────┐
   │ Microservices (per bounded-context)           │
   │ Identity · KYC · Product · Origination ·       │
   │ Decision Engine · Servicing · Recovery · Notif │
   └────┬─────────────────────────────────────────┘
        │
 PostgreSQL · Redis · Object Storage · Kafka (Event Bus)
        │
 Integrasi: OCR/Face · SLIK OJK · Payment Gateway · Email/SMS/Push
```

**Kenapa FastAPI?** Fitur ini padat ML (OCR KTP, face-match, credit scoring) → ekosistem AI native di Python, ML & API satu tempat.

**Kenapa Clean Architecture?** Komponen generik (`core/`: auth, identity, notification, audit) dipisah dari modul lending (`modules/`), sehingga bisa dipakai ulang di produk/bank lain — hemat biaya & waktu.

---

## 5. Model Data — 22 Tabel per Domain

| Domain | Tabel |
|---|---|
| **Identity & Access** | customers (NoCIF), user_accounts, roles, user_roles, devices, biometric_credentials |
| **KYC & Compliance** | kyc_documents, slik_checks |
| **Product & Limit** | loan_products, credit_limits |
| **Origination** | loan_applications, credit_assessments, loan_consents |
| **Servicing** | loans, disbursements, repayment_schedules, payments, transactions |
| **Recovery** | loan_restructurings, collection_activities |
| **Cross-cutting** | notifications, audit_logs |

**Entitas jangkar:** `customers` (identitas nasabah) dan `loans` (kontrak pinjaman). Semua relasi berpusat di keduanya.

---

## 6. Aturan Bisnis Utama

| Kode | Aturan | Cara enforce |
|---|---|---|
| Limit | Nominal ≤ Rp12jt (3 lapis: scoring → policy cap → constraint DB) | `CHECK` + `loan_products` |
| Tenor | 1–12 bulan | `CHECK` |
| **US-07** | Satu nasabah maks **satu pinjaman aktif** | **Filtered unique index** di DB |
| Identitas | 1 NIK = 1 NoCIF seumur hidup | `UNIQUE` |
| Keputusan | Skor + DBR + SLIK → APPROVE / REJECT / REFER | Decision Engine + maker-checker |
| Bayar sebagian | Alokasi waterfall: denda → bunga → pokok | Logika + kolom `alloc_*` |
| Kolektibilitas | DPD 0=Kol1, 1–90=Kol2, 91–120=Kol3, 121–180=Kol4, >180=Kol5 | Job harian |
| Restrukturisasi | Kontrak sama, jadwal lama di-void, kolektibilitas tak direset | `loan_restructurings` + `is_voided` |
| Idempotensi | Cegah bayar ganda | `idempotency_key` UNIQUE |
| Audit | Setiap perubahan status finansial dicatat | `audit_logs` |

---

## 7. Cara Menggunakan Tiap File

### 7.1 Dokumen (`.docx`)
Buka di **Microsoft Word**. Bisa langsung diedit (teks, warna, tabel). Daftar isi & nomor halaman sudah jadi. Semua diagram sudah berupa gambar.

### 7.2 Skema Database (`.sql`) → dbForge / SSMS
1. Buka **dbForge Studio for SQL Server** (atau SSMS)
2. **File → Open** → pilih `schema_v2_sqlserver.sql`
3. **Execute (F5)** → database `xyz_lending` + 22 tabel terbuat
4. Semua constraint, index, dan aturan bisnis ikut dibuat

### 7.3 Diagram (`Diagrams_Editable_v2.zip`)
Ekstrak zip. Ada 3 format per diagram + `README.md` di dalamnya.
- **Mau edit tiap komponen (drag kotak/panah):** pakai file **`.mmd`** →
  buka **app.diagrams.net** → menu **Arrange / Extras → Insert → Advanced → Mermaid** → paste isi `.mmd` → **Insert**. Diagram jadi shape draw.io native yang bisa digeser satuan.
- **Edit cepat online:** paste `.mmd` ke **mermaid.live**
- **Cuma anotasi di atas gambar:** buka file `.drawio`
- **Gambar vektor untuk dokumen:** pakai `.svg`

> Penting: file `.drawio` yang disediakan berisi gambar utuh (bukan shape per-komponen). Untuk diagram yang bisa di-drag per bagian, **selalu mulai dari `.mmd`** lewat fitur Insert Mermaid.

---

## 8. Cara Generate ERD dari Schema (dbForge)

1. Execute `schema_v2_sqlserver.sql` (database jadi)
2. Di **Database Explorer**, klik kanan database `xyz_lending`
3. Pilih **Database Diagram** (atau **Reverse Engineer**)
4. Pilih **semua tabel** → **OK**
5. ERD otomatis muncul lengkap dengan relasi FK — bisa dirapikan & di-export

---

## 9. Alur End-to-End (Ringkas)

```
Register + KYC ──► NoCIF + cek SLIK ──► dapat Limit ──► Simulasi (nominal/tenor)
      └─► Submit + Tanda Tangan Akad ──► cek "pinjaman aktif?" (US-07)
              └─► Decision Engine (skor + DBR + SLIK)
                    ├─ REJECT  ──► notifikasi ditolak
                    ├─ REFER   ──► review Analyst → Approver (maker-checker)
                    └─ APPROVE ──► Pencairan + generate jadwal cicilan
                          └─► Cicilan berjalan
                                ├─ bayar penuh/tepat ──► lunas (PAID_OFF)
                                ├─ bayar sebagian ──► PARTIALLY_PAID (sisa tunggakan)
                                ├─ telat ──► OVERDUE + denda (Kol naik)
                                └─ macet ──► Restrukturisasi (OJK) / Write-off
```

---

## 10. Glosarium

**Istilah Loan/Lending:**
| Istilah | Arti |
|---|---|
| Loan | Pinjaman (kontrak utang yang sudah cair) |
| Loan Application | Pengajuan pinjaman (belum tentu disetujui) |
| Loan Product | Produk pinjaman + aturannya (limit/bunga/tenor) |
| Borrower / Lender | Peminjam / Pemberi pinjaman |
| Disbursement | Pencairan dana |
| Tenor | Jangka waktu pinjaman (bulan) |
| Outstanding | Sisa hutang pokok yang belum dibayar |
| Installment | Cicilan |

**Istilah OJK / Perbankan:**
| Istilah | Arti |
|---|---|
| NoCIF | Nomor identitas nasabah (satu orang satu, seumur hidup) |
| SLIK OJK | Sistem cek riwayat kredit nasional (dahulu BI Checking) |
| Kolektibilitas (Kol 1–5) | Klasifikasi kualitas kredit: Lancar→Macet |
| DPD | Days Past Due — hari keterlambatan |
| DBR | Debt Burden Ratio — rasio cicilan terhadap penghasilan |
| Restrukturisasi | Penyelamatan kredit bermasalah (ubah term, kontrak tetap) |
| Evergreening | Praktik terlarang menyamarkan kredit macet (dihindari sistem ini) |
| Maker–Checker | Pengaju ≠ pemutus (kontrol internal) |
| Akad | Perjanjian pinjaman yang disetujui nasabah |

---

## 11. Poin untuk Presentasi Interview

Highlight yang menunjukkan cara berpikir Solution Engineer bank:
1. **Tidak hardcode "12jt"** — dibuat kebijakan produk yang configurable (`loan_products`), di-cap 3 lapis. *"Kalau plafon naik jadi Rp25jt, cukup ubah konfigurasi."*
2. **Pisah identitas (NoCIF) vs akun login** — paham beda data nasabah vs kredensial, dasar pelaporan OJK.
3. **US-07 di-enforce di level database** (filtered unique index), bukan cuma di aplikasi. *"Pengaman terakhir tetap di data layer."*
4. **Restrukturisasi model OJK yang benar** — anti-evergreening, kolektibilitas tak direset. Menunjukkan paham regulasi, bukan sekadar CRUD.
5. **Maker–checker** — sadar kontrol internal bank (pengaju ≠ pemutus).
6. **Clean Architecture** — komponen generik reusable, hemat biaya produk berikutnya.
7. **FastAPI dipilih kontekstual** — karena fitur ML-heavy (OCR, face-match, scoring), bukan asal pilih.

---

## 12. Struktur Paket

```
outputs/
├── README.md                        ← file ini
├── SDD_PinjamanOnline_v2.docx       ← dokumen utama
├── SDD_PinjamanOnline_v2.pdf        ← versi PDF
├── SDD_PinjamanOnline_v2.md         ← sumber markdown
├── schema_v2_sqlserver.sql          ← skema database (22 tabel)
└── Diagrams_Editable_v2.zip         ← 12 diagram (mmd/drawio/svg) + panduan
```

*Disiapkan oleh Tim Solution Engineering — PT. XYZ · 2026*
