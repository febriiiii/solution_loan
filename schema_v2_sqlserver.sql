-- ================================================================
-- PT. XYZ — Digital Lending (Aplikasi Pinjaman Online)
-- Database Schema — SQL Server (T-SQL) — v2.0 (Enterprise / OJK-aligned)
-- Mengacu pada SDD v2 §5 (ERD 3-domain).
-- 22 tabel: Identity/Access, KYC/Compliance, Product/Limit,
--           Origination, Servicing, Recovery, Cross-cutting.
-- ================================================================

USE master;
GO
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'xyz_lending')
    CREATE DATABASE [xyz_lending] COLLATE Latin1_General_CI_AS;
GO
USE [xyz_lending];
GO

-- ================================================================
-- DROP (urutan terbalik terhadap dependensi FK)
-- ================================================================
IF OBJECT_ID('dbo.audit_logs','U')           IS NOT NULL DROP TABLE dbo.audit_logs;
IF OBJECT_ID('dbo.notifications','U')         IS NOT NULL DROP TABLE dbo.notifications;
IF OBJECT_ID('dbo.collection_activities','U') IS NOT NULL DROP TABLE dbo.collection_activities;
IF OBJECT_ID('dbo.transactions','U')          IS NOT NULL DROP TABLE dbo.transactions;
IF OBJECT_ID('dbo.payments','U')              IS NOT NULL DROP TABLE dbo.payments;
IF OBJECT_ID('dbo.repayment_schedules','U')   IS NOT NULL DROP TABLE dbo.repayment_schedules;
IF OBJECT_ID('dbo.loan_restructurings','U')   IS NOT NULL DROP TABLE dbo.loan_restructurings;
IF OBJECT_ID('dbo.disbursements','U')         IS NOT NULL DROP TABLE dbo.disbursements;
IF OBJECT_ID('dbo.loans','U')                 IS NOT NULL DROP TABLE dbo.loans;
IF OBJECT_ID('dbo.loan_consents','U')         IS NOT NULL DROP TABLE dbo.loan_consents;
IF OBJECT_ID('dbo.credit_assessments','U')    IS NOT NULL DROP TABLE dbo.credit_assessments;
IF OBJECT_ID('dbo.loan_applications','U')     IS NOT NULL DROP TABLE dbo.loan_applications;
IF OBJECT_ID('dbo.credit_limits','U')         IS NOT NULL DROP TABLE dbo.credit_limits;
IF OBJECT_ID('dbo.loan_products','U')         IS NOT NULL DROP TABLE dbo.loan_products;
IF OBJECT_ID('dbo.slik_checks','U')           IS NOT NULL DROP TABLE dbo.slik_checks;
IF OBJECT_ID('dbo.kyc_documents','U')         IS NOT NULL DROP TABLE dbo.kyc_documents;
IF OBJECT_ID('dbo.biometric_credentials','U') IS NOT NULL DROP TABLE dbo.biometric_credentials;
IF OBJECT_ID('dbo.devices','U')               IS NOT NULL DROP TABLE dbo.devices;
IF OBJECT_ID('dbo.user_roles','U')            IS NOT NULL DROP TABLE dbo.user_roles;
IF OBJECT_ID('dbo.roles','U')                 IS NOT NULL DROP TABLE dbo.roles;
IF OBJECT_ID('dbo.user_accounts','U')         IS NOT NULL DROP TABLE dbo.user_accounts;
IF OBJECT_ID('dbo.customers','U')             IS NOT NULL DROP TABLE dbo.customers;
GO

-- ================================================================
-- DOMAIN 1 — IDENTITY & ACCESS
-- ================================================================

-- 1. CUSTOMERS (CIF) — identitas nasabah, satu NoCIF seumur hidup.
CREATE TABLE dbo.customers (
    customer_id   UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_cust_id   DEFAULT NEWID(),
    no_cif        VARCHAR(20)      NOT NULL,                 -- NoCIF (unik)
    nik_ktp       VARCHAR(16)      NOT NULL,                 -- NIK e-KTP (unik)
    full_name     NVARCHAR(150)    NOT NULL,
    birth_place   NVARCHAR(100)    NULL,
    birth_date    DATE             NULL,
    gender        CHAR(1)          NULL,                     -- L | P
    address       NVARCHAR(400)    NULL,
    bank_account_no VARCHAR(34)    NULL,                     -- rekening pencairan
    kyc_status    VARCHAR(20)      NOT NULL CONSTRAINT df_cust_kyc DEFAULT 'PENDING',
    created_at    DATETIME2(0)     NOT NULL CONSTRAINT df_cust_created DEFAULT SYSUTCDATETIME(),
    updated_at    DATETIME2(0)     NOT NULL CONSTRAINT df_cust_updated DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_customers      PRIMARY KEY (customer_id),
    CONSTRAINT uq_cust_no_cif    UNIQUE (no_cif),
    CONSTRAINT uq_cust_nik       UNIQUE (nik_ktp),          -- BR-01: 1 NIK = 1 CIF
    CONSTRAINT chk_cust_kyc      CHECK (kyc_status IN ('PENDING','VERIFIED','REJECTED')),
    CONSTRAINT chk_cust_gender   CHECK (gender IS NULL OR gender IN ('L','P'))
);
GO

-- 2. USER_ACCOUNTS — kredensial akses (terpisah dari identitas).
CREATE TABLE dbo.user_accounts (
    user_id       UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_ua_id DEFAULT NEWID(),
    customer_id   UNIQUEIDENTIFIER NOT NULL,
    email         NVARCHAR(255)    NOT NULL,
    phone         VARCHAR(20)      NOT NULL,
    password_hash NVARCHAR(255)    NOT NULL,
    status        VARCHAR(20)      NOT NULL CONSTRAINT df_ua_status DEFAULT 'PENDING',
    failed_login_count TINYINT     NOT NULL CONSTRAINT df_ua_flc DEFAULT 0,
    last_login_at DATETIME2(0)     NULL,
    created_at    DATETIME2(0)     NOT NULL CONSTRAINT df_ua_created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_user_accounts  PRIMARY KEY (user_id),
    CONSTRAINT fk_ua_customer    FOREIGN KEY (customer_id) REFERENCES dbo.customers(customer_id),
    CONSTRAINT uq_ua_email       UNIQUE (email),
    CONSTRAINT uq_ua_phone       UNIQUE (phone),
    CONSTRAINT chk_ua_status     CHECK (status IN ('PENDING','ACTIVE','LOCKED','SUSPENDED'))
);
GO

-- 3. ROLES (RBAC) & 4. USER_ROLES (maker-checker, least privilege)
CREATE TABLE dbo.roles (
    role_id  UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_role_id DEFAULT NEWID(),
    code     VARCHAR(30)      NOT NULL,   -- BORROWER|ANALYST|APPROVER|COLLECTION|ADMIN
    name     NVARCHAR(100)    NOT NULL,
    CONSTRAINT pk_roles   PRIMARY KEY (role_id),
    CONSTRAINT uq_role_code UNIQUE (code)
);
GO
CREATE TABLE dbo.user_roles (
    user_id UNIQUEIDENTIFIER NOT NULL,
    role_id UNIQUEIDENTIFIER NOT NULL,
    CONSTRAINT pk_user_roles PRIMARY KEY (user_id, role_id),
    CONSTRAINT fk_ur_user FOREIGN KEY (user_id) REFERENCES dbo.user_accounts(user_id),
    CONSTRAINT fk_ur_role FOREIGN KEY (role_id) REFERENCES dbo.roles(role_id)
);
GO

-- 5. DEVICES — perangkat mobile terdaftar.
CREATE TABLE dbo.devices (
    device_id     UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_dev_id DEFAULT NEWID(),
    user_id       UNIQUEIDENTIFIER NOT NULL,
    platform      VARCHAR(10)      NOT NULL,   -- IOS | ANDROID
    device_name   NVARCHAR(150)    NULL,
    push_token    NVARCHAR(500)    NULL,
    is_active     BIT              NOT NULL CONSTRAINT df_dev_active DEFAULT 1,
    last_seen_at  DATETIME2(0)     NULL,
    registered_at DATETIME2(0)     NOT NULL CONSTRAINT df_dev_reg DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_devices     PRIMARY KEY (device_id),
    CONSTRAINT fk_dev_user    FOREIGN KEY (user_id) REFERENCES dbo.user_accounts(user_id),
    CONSTRAINT chk_dev_platform CHECK (platform IN ('IOS','ANDROID'))
);
GO

-- 6. BIOMETRIC_CREDENTIALS — public key device-bound (login biometric).
CREATE TABLE dbo.biometric_credentials (
    credential_id UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_bio_id DEFAULT NEWID(),
    user_id       UNIQUEIDENTIFIER NOT NULL,
    device_id     UNIQUEIDENTIFIER NOT NULL,
    public_key    NVARCHAR(MAX)    NOT NULL,
    algorithm     VARCHAR(20)      NOT NULL CONSTRAINT df_bio_algo DEFAULT 'ES256',
    is_active     BIT              NOT NULL CONSTRAINT df_bio_active DEFAULT 1,
    registered_at DATETIME2(0)     NOT NULL CONSTRAINT df_bio_reg DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_biometric_credentials PRIMARY KEY (credential_id),
    CONSTRAINT fk_bio_user   FOREIGN KEY (user_id)   REFERENCES dbo.user_accounts(user_id),
    CONSTRAINT fk_bio_device FOREIGN KEY (device_id) REFERENCES dbo.devices(device_id)
);
GO

-- ================================================================
-- DOMAIN 2 — KYC & COMPLIANCE
-- ================================================================

-- 7. KYC_DOCUMENTS — KTP & selfie + hasil OCR/face-match.
CREATE TABLE dbo.kyc_documents (
    document_id      UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_kyc_id DEFAULT NEWID(),
    customer_id      UNIQUEIDENTIFIER NOT NULL,
    ktp_image_url    NVARCHAR(500)    NOT NULL,
    selfie_image_url NVARCHAR(500)    NOT NULL,
    ocr_status       VARCHAR(20)      NOT NULL CONSTRAINT df_kyc_ocr DEFAULT 'PENDING',
    face_match_score DECIMAL(5,2)     NULL,       -- 0.00 - 100.00
    verified_at      DATETIME2(0)     NULL,
    created_at       DATETIME2(0)     NOT NULL CONSTRAINT df_kyc_created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_kyc_documents PRIMARY KEY (document_id),
    CONSTRAINT fk_kyc_customer  FOREIGN KEY (customer_id) REFERENCES dbo.customers(customer_id),
    CONSTRAINT chk_kyc_ocr      CHECK (ocr_status IN ('PENDING','PASSED','FAILED')),
    CONSTRAINT chk_kyc_face     CHECK (face_match_score IS NULL OR (face_match_score BETWEEN 0 AND 100))
);
GO

-- 8. SLIK_CHECKS — hasil pengecekan biro kredit OJK.
CREATE TABLE dbo.slik_checks (
    slik_id          UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_slik_id DEFAULT NEWID(),
    customer_id      UNIQUEIDENTIFIER NOT NULL,
    bureau_reference NVARCHAR(100)    NULL,
    bureau_score     INT              NULL,
    result           VARCHAR(20)      NOT NULL,   -- CLEAR | WATCHLIST | BAD
    checked_at       DATETIME2(0)     NOT NULL CONSTRAINT df_slik_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_slik_checks  PRIMARY KEY (slik_id),
    CONSTRAINT fk_slik_customer FOREIGN KEY (customer_id) REFERENCES dbo.customers(customer_id),
    CONSTRAINT chk_slik_result CHECK (result IN ('CLEAR','WATCHLIST','BAD'))
);
GO

-- ================================================================
-- DOMAIN 3 — PRODUCT & LIMIT
-- ================================================================

-- 9. LOAN_PRODUCTS — kebijakan produk (anti-hardcode limit/tenor/bunga).
CREATE TABLE dbo.loan_products (
    product_id     UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_prod_id DEFAULT NEWID(),
    name           NVARCHAR(100)    NOT NULL,
    min_amount     DECIMAL(15,2)    NOT NULL CONSTRAINT df_prod_min DEFAULT 1000000,
    max_amount     DECIMAL(15,2)    NOT NULL CONSTRAINT df_prod_max DEFAULT 12000000, -- ceiling (BR-03)
    allowed_tenors VARCHAR(50)      NOT NULL CONSTRAINT df_prod_ten DEFAULT '3,6,9,12',
    max_tenor      TINYINT          NOT NULL CONSTRAINT df_prod_mt  DEFAULT 12,
    interest_type  VARCHAR(10)      NOT NULL CONSTRAINT df_prod_it  DEFAULT 'FLAT',
    interest_rate  DECIMAL(6,4)     NOT NULL,   -- per bulan, mis. 0.0200
    admin_fee_rate DECIMAL(6,4)     NOT NULL CONSTRAINT df_prod_af DEFAULT 0,
    penalty_rate   DECIMAL(6,4)     NOT NULL CONSTRAINT df_prod_pr DEFAULT 0.0010, -- per hari
    is_active      BIT              NOT NULL CONSTRAINT df_prod_active DEFAULT 1,
    created_at     DATETIME2(0)     NOT NULL CONSTRAINT df_prod_created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_loan_products PRIMARY KEY (product_id),
    CONSTRAINT chk_prod_amounts CHECK (min_amount > 0 AND max_amount >= min_amount),
    CONSTRAINT chk_prod_maxcap  CHECK (max_amount <= 12000000),  -- kebijakan SSOT
    CONSTRAINT chk_prod_tenor   CHECK (max_tenor BETWEEN 1 AND 12),
    CONSTRAINT chk_prod_itype   CHECK (interest_type IN ('FLAT','EFFECTIVE'))
);
GO

-- 10. CREDIT_LIMITS — plafon per nasabah (hasil scoring, di-cap kebijakan).
CREATE TABLE dbo.credit_limits (
    limit_id       UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_lim_id DEFAULT NEWID(),
    customer_id    UNIQUEIDENTIFIER NOT NULL,
    product_id     UNIQUEIDENTIFIER NOT NULL,
    approved_limit DECIMAL(15,2)    NOT NULL,   -- MIN(score, product.max_amount) (BR-03)
    used_amount    DECIMAL(15,2)    NOT NULL CONSTRAINT df_lim_used DEFAULT 0,
    status         VARCHAR(20)      NOT NULL CONSTRAINT df_lim_status DEFAULT 'ACTIVE',
    valid_until    DATE             NULL,
    updated_at     DATETIME2(0)     NOT NULL CONSTRAINT df_lim_upd DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_credit_limits PRIMARY KEY (limit_id),
    CONSTRAINT fk_lim_customer  FOREIGN KEY (customer_id) REFERENCES dbo.customers(customer_id),
    CONSTRAINT fk_lim_product   FOREIGN KEY (product_id)  REFERENCES dbo.loan_products(product_id),
    CONSTRAINT uq_lim_cust_prod UNIQUE (customer_id, product_id),
    CONSTRAINT chk_lim_amount   CHECK (approved_limit >= 0 AND approved_limit <= 12000000),
    CONSTRAINT chk_lim_used     CHECK (used_amount >= 0),
    CONSTRAINT chk_lim_status   CHECK (status IN ('ACTIVE','SUSPENDED'))
);
GO

-- ================================================================
-- DOMAIN 4 — ORIGINATION
-- ================================================================

-- 11. LOAN_APPLICATIONS — pengajuan (limit & tenor di-enforce).
CREATE TABLE dbo.loan_applications (
    application_id  UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_app_id DEFAULT NEWID(),
    customer_id     UNIQUEIDENTIFIER NOT NULL,
    product_id      UNIQUEIDENTIFIER NOT NULL,
    amount          DECIMAL(15,2)    NOT NULL,   -- <= 12.000.000 (BR-04)
    tenor_months    TINYINT          NOT NULL,   -- 1..12
    purpose         NVARCHAR(100)    NULL,
    status          VARCHAR(20)      NOT NULL CONSTRAINT df_app_status DEFAULT 'SUBMITTED',
    decision_reason NVARCHAR(500)    NULL,
    submitted_at    DATETIME2(0)     NOT NULL CONSTRAINT df_app_sub DEFAULT SYSUTCDATETIME(),
    decided_at      DATETIME2(0)     NULL,
    CONSTRAINT pk_loan_applications PRIMARY KEY (application_id),
    CONSTRAINT fk_app_customer FOREIGN KEY (customer_id) REFERENCES dbo.customers(customer_id),
    CONSTRAINT fk_app_product  FOREIGN KEY (product_id)  REFERENCES dbo.loan_products(product_id),
    CONSTRAINT chk_app_amount  CHECK (amount > 0 AND amount <= 12000000),
    CONSTRAINT chk_app_tenor   CHECK (tenor_months BETWEEN 1 AND 12),
    CONSTRAINT chk_app_status  CHECK (status IN ('DRAFT','SUBMITTED','UNDER_REVIEW','APPROVED','REJECTED','CANCELLED','EXPIRED'))
);
GO

-- 12. CREDIT_ASSESSMENTS — hasil Decision Engine (1-1 dengan aplikasi).
CREATE TABLE dbo.credit_assessments (
    assessment_id  UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_ca_id DEFAULT NEWID(),
    application_id UNIQUEIDENTIFIER NOT NULL,
    slik_id        UNIQUEIDENTIFIER NULL,
    credit_score   SMALLINT         NOT NULL,   -- 0..1000
    risk_grade     VARCHAR(2)       NOT NULL,   -- A..E
    dbr_ratio      DECIMAL(5,2)     NULL,       -- Debt Burden Ratio (%)
    decision       VARCHAR(10)      NOT NULL,   -- APPROVE | REJECT | REFER
    notes          NVARCHAR(1000)   NULL,
    assessed_at    DATETIME2(0)     NOT NULL CONSTRAINT df_ca_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_credit_assessments PRIMARY KEY (assessment_id),
    CONSTRAINT uq_ca_application UNIQUE (application_id),          -- 1-1
    CONSTRAINT fk_ca_application FOREIGN KEY (application_id) REFERENCES dbo.loan_applications(application_id),
    CONSTRAINT fk_ca_slik        FOREIGN KEY (slik_id)        REFERENCES dbo.slik_checks(slik_id),
    CONSTRAINT chk_ca_score      CHECK (credit_score BETWEEN 0 AND 1000),
    CONSTRAINT chk_ca_grade      CHECK (risk_grade IN ('A','B','C','D','E')),
    CONSTRAINT chk_ca_decision   CHECK (decision IN ('APPROVE','REJECT','REFER'))
);
GO

-- 13. LOAN_CONSENTS — akad & tanda tangan digital (prasyarat pencairan).
CREATE TABLE dbo.loan_consents (
    consent_id     UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_con_id DEFAULT NEWID(),
    application_id UNIQUEIDENTIFIER NOT NULL,
    type           VARCHAR(20)      NOT NULL CONSTRAINT df_con_type DEFAULT 'LOAN_AGREEMENT',
    signature_ref  NVARCHAR(200)    NOT NULL,
    document_url   NVARCHAR(500)    NULL,
    signed_at      DATETIME2(0)     NOT NULL CONSTRAINT df_con_at DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_loan_consents PRIMARY KEY (consent_id),
    CONSTRAINT fk_con_application FOREIGN KEY (application_id) REFERENCES dbo.loan_applications(application_id),
    CONSTRAINT chk_con_type CHECK (type IN ('LOAN_AGREEMENT','RESTRUCTURING'))
);
GO

-- ================================================================
-- DOMAIN 5 — SERVICING
-- ================================================================

-- 14. LOANS — kontrak aktif (+ kolektibilitas, DPD, flag restruktur).
CREATE TABLE dbo.loans (
    loan_id             UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_loan_id DEFAULT NEWID(),
    application_id      UNIQUEIDENTIFIER NOT NULL,
    customer_id         UNIQUEIDENTIFIER NOT NULL,
    principal           DECIMAL(15,2)    NOT NULL,
    interest_rate       DECIMAL(6,4)     NOT NULL,
    interest_type       VARCHAR(10)      NOT NULL CONSTRAINT df_loan_it DEFAULT 'FLAT',
    tenor_months        TINYINT          NOT NULL,
    monthly_installment DECIMAL(15,2)    NOT NULL,
    outstanding_balance DECIMAL(15,2)    NOT NULL,
    status              VARCHAR(20)      NOT NULL CONSTRAINT df_loan_status DEFAULT 'PENDING_DISBURSEMENT',
    collectibility      VARCHAR(6)       NOT NULL CONSTRAINT df_loan_kol DEFAULT 'KOL_1',
    days_past_due       INT              NOT NULL CONSTRAINT df_loan_dpd DEFAULT 0,
    is_restructured     BIT              NOT NULL CONSTRAINT df_loan_isr DEFAULT 0,
    restructure_count   TINYINT          NOT NULL CONSTRAINT df_loan_rc  DEFAULT 0,
    disbursed_at        DATETIME2(0)     NULL,
    maturity_date       DATE             NULL,
    created_at          DATETIME2(0)     NOT NULL CONSTRAINT df_loan_created DEFAULT SYSUTCDATETIME(),
    updated_at          DATETIME2(0)     NOT NULL CONSTRAINT df_loan_updated DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_loans PRIMARY KEY (loan_id),
    CONSTRAINT uq_loan_application UNIQUE (application_id),
    CONSTRAINT fk_loan_application FOREIGN KEY (application_id) REFERENCES dbo.loan_applications(application_id),
    CONSTRAINT fk_loan_customer    FOREIGN KEY (customer_id)    REFERENCES dbo.customers(customer_id),
    CONSTRAINT chk_loan_principal   CHECK (principal > 0),
    CONSTRAINT chk_loan_outstanding CHECK (outstanding_balance >= 0),
    CONSTRAINT chk_loan_status CHECK (status IN ('PENDING_DISBURSEMENT','ACTIVE','OVERDUE','RESTRUCTURED','PAID_OFF','WRITTEN_OFF')),
    CONSTRAINT chk_loan_kol    CHECK (collectibility IN ('KOL_1','KOL_2','KOL_3','KOL_4','KOL_5')),
    CONSTRAINT chk_loan_dpd    CHECK (days_past_due >= 0)
);
GO

-- BR-05 / US-07: satu nasabah maksimal SATU pinjaman aktif.
-- Diterapkan di level DB via filtered unique index.
CREATE UNIQUE INDEX uq_loan_one_active
    ON dbo.loans (customer_id)
    WHERE status IN ('PENDING_DISBURSEMENT','ACTIVE','OVERDUE','RESTRUCTURED');
GO

-- 15. DISBURSEMENTS — pencairan dana ke rekening nasabah.
CREATE TABLE dbo.disbursements (
    disbursement_id  UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_disb_id DEFAULT NEWID(),
    loan_id          UNIQUEIDENTIFIER NOT NULL,
    amount           DECIMAL(15,2)    NOT NULL,
    bank_account_no  VARCHAR(34)      NOT NULL,
    gateway_reference NVARCHAR(100)   NULL,
    status           VARCHAR(20)      NOT NULL CONSTRAINT df_disb_status DEFAULT 'PENDING',
    disbursed_at     DATETIME2(0)     NULL,
    created_at       DATETIME2(0)     NOT NULL CONSTRAINT df_disb_created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_disbursements PRIMARY KEY (disbursement_id),
    CONSTRAINT fk_disb_loan FOREIGN KEY (loan_id) REFERENCES dbo.loans(loan_id),
    CONSTRAINT chk_disb_amount CHECK (amount > 0),
    CONSTRAINT chk_disb_status CHECK (status IN ('PENDING','PROCESSING','SUCCESS','FAILED'))
);
GO

-- ================================================================
-- DOMAIN 6 — RECOVERY (dibuat sebelum repayment_schedules krn direferensikan)
-- ================================================================

-- 19. LOAN_RESTRUCTURINGS — jejak restrukturisasi (model OJK, anti-evergreening).
CREATE TABLE dbo.loan_restructurings (
    restructuring_id   UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_rst_id DEFAULT NEWID(),
    loan_id            UNIQUEIDENTIFIER NOT NULL,
    method             VARCHAR(20)      NOT NULL,   -- TENOR_EXTENSION|RATE_REDUCTION|...
    reason             NVARCHAR(500)    NULL,
    old_tenor          TINYINT          NULL,
    new_tenor          TINYINT          NULL,
    old_installment    DECIMAL(15,2)    NULL,
    new_installment    DECIMAL(15,2)    NULL,
    old_collectibility VARCHAR(6)       NULL,       -- ditahan, tidak reset (BR-12)
    approved_by        UNIQUEIDENTIFIER NULL,       -- user_accounts.user_id (Approver)
    effective_date     DATE             NOT NULL,
    created_at         DATETIME2(0)     NOT NULL CONSTRAINT df_rst_created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_loan_restructurings PRIMARY KEY (restructuring_id),
    CONSTRAINT fk_rst_loan     FOREIGN KEY (loan_id)     REFERENCES dbo.loans(loan_id),
    CONSTRAINT fk_rst_approver FOREIGN KEY (approved_by) REFERENCES dbo.user_accounts(user_id),
    CONSTRAINT chk_rst_method  CHECK (method IN ('TENOR_EXTENSION','RATE_REDUCTION','PRINCIPAL_CUT','INTEREST_CUT','ADD_FACILITY','EQUITY_CONV'))
);
GO

-- ================================================================
-- DOMAIN 5 (lanjut) — SERVICING
-- ================================================================

-- 16. REPAYMENT_SCHEDULES — jadwal cicilan (+ partial & void saat restruktur).
CREATE TABLE dbo.repayment_schedules (
    installment_id      UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_rs_id DEFAULT NEWID(),
    loan_id             UNIQUEIDENTIFIER NOT NULL,
    restructuring_id    UNIQUEIDENTIFIER NULL,       -- jadwal hasil restrukturisasi
    installment_no      TINYINT          NOT NULL,
    due_date            DATE             NOT NULL,
    amount_due          DECIMAL(15,2)    NOT NULL,
    principal_component DECIMAL(15,2)    NOT NULL,
    interest_component  DECIMAL(15,2)    NOT NULL,
    penalty_amount      DECIMAL(15,2)    NOT NULL CONSTRAINT df_rs_pen DEFAULT 0,
    paid_amount         DECIMAL(15,2)    NOT NULL CONSTRAINT df_rs_paid DEFAULT 0,
    status              VARCHAR(20)      NOT NULL CONSTRAINT df_rs_status DEFAULT 'PENDING',
    is_voided           BIT              NOT NULL CONSTRAINT df_rs_void DEFAULT 0,
    paid_at             DATETIME2(0)     NULL,
    created_at          DATETIME2(0)     NOT NULL CONSTRAINT df_rs_created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_repayment_schedules PRIMARY KEY (installment_id),
    CONSTRAINT fk_rs_loan          FOREIGN KEY (loan_id)          REFERENCES dbo.loans(loan_id),
    CONSTRAINT fk_rs_restructuring FOREIGN KEY (restructuring_id) REFERENCES dbo.loan_restructurings(restructuring_id),
    CONSTRAINT chk_rs_amounts CHECK (amount_due >= 0 AND paid_amount >= 0 AND penalty_amount >= 0),
    CONSTRAINT chk_rs_status  CHECK (status IN ('PENDING','PARTIALLY_PAID','PAID','OVERDUE','VOIDED'))
);
GO

-- 17. PAYMENTS — pembayaran + rincian alokasi waterfall (BR-09), idempoten.
CREATE TABLE dbo.payments (
    payment_id      UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_pay_id DEFAULT NEWID(),
    loan_id         UNIQUEIDENTIFIER NOT NULL,
    installment_id  UNIQUEIDENTIFIER NULL,       -- NULL bila pelunasan sekaligus
    amount          DECIMAL(15,2)    NOT NULL,
    alloc_penalty   DECIMAL(15,2)    NOT NULL CONSTRAINT df_pay_ap DEFAULT 0,
    alloc_interest  DECIMAL(15,2)    NOT NULL CONSTRAINT df_pay_ai DEFAULT 0,
    alloc_principal DECIMAL(15,2)    NOT NULL CONSTRAINT df_pay_apr DEFAULT 0,
    method          VARCHAR(20)      NOT NULL,   -- VA | TRANSFER | QRIS
    gateway_reference NVARCHAR(100)  NULL,
    idempotency_key VARCHAR(100)     NULL,
    status          VARCHAR(20)      NOT NULL CONSTRAINT df_pay_status DEFAULT 'PENDING',
    failure_reason  NVARCHAR(500)    NULL,
    paid_at         DATETIME2(0)     NULL,
    created_at      DATETIME2(0)     NOT NULL CONSTRAINT df_pay_created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_payments PRIMARY KEY (payment_id),
    CONSTRAINT uq_pay_idem UNIQUE (idempotency_key),           -- BR-15
    CONSTRAINT fk_pay_loan        FOREIGN KEY (loan_id)        REFERENCES dbo.loans(loan_id),
    CONSTRAINT fk_pay_installment FOREIGN KEY (installment_id) REFERENCES dbo.repayment_schedules(installment_id),
    CONSTRAINT chk_pay_amount CHECK (amount > 0),
    CONSTRAINT chk_pay_method CHECK (method IN ('VA','TRANSFER','QRIS','CARD')),
    CONSTRAINT chk_pay_status CHECK (status IN ('PENDING','SUCCESS','FAILED','REVERSED'))
);
GO

-- 18. TRANSACTIONS — buku besar mutasi (pencairan/pembayaran/denda/reversal).
CREATE TABLE dbo.transactions (
    transaction_id UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_tx_id DEFAULT NEWID(),
    customer_id    UNIQUEIDENTIFIER NOT NULL,
    loan_id        UNIQUEIDENTIFIER NULL,
    payment_id     UNIQUEIDENTIFIER NULL,
    type           VARCHAR(20)      NOT NULL,   -- DISBURSEMENT|REPAYMENT|PENALTY|WAIVER|REVERSAL
    amount         DECIMAL(15,2)    NOT NULL,
    reference      NVARCHAR(100)    NULL,
    description    NVARCHAR(500)    NULL,
    created_at     DATETIME2(0)     NOT NULL CONSTRAINT df_tx_created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_transactions PRIMARY KEY (transaction_id),
    CONSTRAINT fk_tx_customer FOREIGN KEY (customer_id) REFERENCES dbo.customers(customer_id),
    CONSTRAINT fk_tx_loan     FOREIGN KEY (loan_id)     REFERENCES dbo.loans(loan_id),
    CONSTRAINT fk_tx_payment  FOREIGN KEY (payment_id)  REFERENCES dbo.payments(payment_id),
    CONSTRAINT chk_tx_amount CHECK (amount > 0),
    CONSTRAINT chk_tx_type   CHECK (type IN ('DISBURSEMENT','REPAYMENT','PENALTY','WAIVER','REVERSAL'))
);
GO

-- 20. COLLECTION_ACTIVITIES — aktivitas penagihan.
CREATE TABLE dbo.collection_activities (
    activity_id UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_col_id DEFAULT NEWID(),
    loan_id     UNIQUEIDENTIFIER NOT NULL,
    channel     VARCHAR(10)      NOT NULL,   -- SMS | CALL | FIELD
    result      NVARCHAR(300)    NULL,
    officer_id  UNIQUEIDENTIFIER NULL,       -- user_accounts.user_id (Collection)
    created_at  DATETIME2(0)     NOT NULL CONSTRAINT df_col_created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_collection_activities PRIMARY KEY (activity_id),
    CONSTRAINT fk_col_loan    FOREIGN KEY (loan_id)    REFERENCES dbo.loans(loan_id),
    CONSTRAINT fk_col_officer FOREIGN KEY (officer_id) REFERENCES dbo.user_accounts(user_id),
    CONSTRAINT chk_col_channel CHECK (channel IN ('SMS','CALL','FIELD'))
);
GO

-- ================================================================
-- DOMAIN 7 — CROSS-CUTTING
-- ================================================================

-- 21. NOTIFICATIONS — riwayat notifikasi (email/SMS/push).
CREATE TABLE dbo.notifications (
    notification_id UNIQUEIDENTIFIER NOT NULL CONSTRAINT df_notif_id DEFAULT NEWID(),
    customer_id     UNIQUEIDENTIFIER NOT NULL,
    channel         VARCHAR(10)      NOT NULL,   -- EMAIL | SMS | PUSH
    template_code   VARCHAR(50)      NOT NULL,
    payload         NVARCHAR(MAX)    NULL,
    status          VARCHAR(10)      NOT NULL CONSTRAINT df_notif_status DEFAULT 'QUEUED',
    retry_count     TINYINT          NOT NULL CONSTRAINT df_notif_retry DEFAULT 0,
    sent_at         DATETIME2(0)     NULL,
    created_at      DATETIME2(0)     NOT NULL CONSTRAINT df_notif_created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_notifications PRIMARY KEY (notification_id),
    CONSTRAINT fk_notif_customer FOREIGN KEY (customer_id) REFERENCES dbo.customers(customer_id),
    CONSTRAINT chk_notif_channel CHECK (channel IN ('EMAIL','SMS','PUSH')),
    CONSTRAINT chk_notif_status  CHECK (status IN ('QUEUED','SENT','FAILED'))
);
GO

-- 22. AUDIT_LOGS — jejak audit immutable (BR-14). Generic (entity_name, id, before/after).
CREATE TABLE dbo.audit_logs (
    audit_id     BIGINT IDENTITY(1,1) NOT NULL,
    entity_name  VARCHAR(50)      NOT NULL,   -- mis. 'loans', 'loan_applications'
    entity_id    UNIQUEIDENTIFIER NULL,
    action       VARCHAR(30)      NOT NULL,   -- CREATE | UPDATE | STATUS_CHANGE | DECISION
    actor_id     UNIQUEIDENTIFIER NULL,       -- user_accounts.user_id / NULL utk sistem
    old_value    NVARCHAR(MAX)    NULL,
    new_value    NVARCHAR(MAX)    NULL,
    created_at   DATETIME2(0)     NOT NULL CONSTRAINT df_audit_created DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_audit_logs PRIMARY KEY (audit_id)
);
GO

-- ================================================================
-- INDEXES (performa query umum)
-- ================================================================
CREATE INDEX ix_ua_customer        ON dbo.user_accounts(customer_id);
CREATE INDEX ix_dev_user           ON dbo.devices(user_id);
CREATE INDEX ix_bio_user           ON dbo.biometric_credentials(user_id);
CREATE INDEX ix_kyc_customer       ON dbo.kyc_documents(customer_id);
CREATE INDEX ix_slik_customer      ON dbo.slik_checks(customer_id);
CREATE INDEX ix_lim_customer       ON dbo.credit_limits(customer_id);
CREATE INDEX ix_app_customer       ON dbo.loan_applications(customer_id);
CREATE INDEX ix_app_status         ON dbo.loan_applications(status);
CREATE INDEX ix_ca_application     ON dbo.credit_assessments(application_id);
CREATE INDEX ix_con_application    ON dbo.loan_consents(application_id);
CREATE INDEX ix_loan_customer      ON dbo.loans(customer_id);
CREATE INDEX ix_loan_status        ON dbo.loans(status);
CREATE INDEX ix_loan_collect       ON dbo.loans(collectibility);
CREATE INDEX ix_disb_loan          ON dbo.disbursements(loan_id);
CREATE INDEX ix_rst_loan           ON dbo.loan_restructurings(loan_id);
CREATE INDEX ix_rs_loan            ON dbo.repayment_schedules(loan_id);
CREATE INDEX ix_rs_due             ON dbo.repayment_schedules(due_date);
CREATE INDEX ix_rs_status          ON dbo.repayment_schedules(status);
CREATE INDEX ix_pay_loan           ON dbo.payments(loan_id);
CREATE INDEX ix_pay_status         ON dbo.payments(status);
CREATE INDEX ix_tx_customer        ON dbo.transactions(customer_id);
CREATE INDEX ix_tx_loan            ON dbo.transactions(loan_id);
CREATE INDEX ix_col_loan           ON dbo.collection_activities(loan_id);
CREATE INDEX ix_notif_customer     ON dbo.notifications(customer_id);
CREATE INDEX ix_audit_entity       ON dbo.audit_logs(entity_name, entity_id);
GO

PRINT 'Schema xyz_lending v2 selesai — 22 tabel, constraint bisnis (limit/tenor/kolektibilitas), 1 filtered unique index (US-07), + index.';
GO
