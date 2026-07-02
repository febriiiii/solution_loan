SELECT *
FROM customers c
    -- identitas & akses (borrower)
    INNER JOIN user_accounts ua ON ua.customer_id = c.customer_id
    LEFT  JOIN devices d        ON d.user_id  = ua.user_id
    LEFT  JOIN biometric_credentials bc
                                ON bc.user_id = ua.user_id AND bc.device_id = d.device_id
    -- KYC & compliance
    LEFT  JOIN kyc_documents kyc ON kyc.customer_id  = c.customer_id
    LEFT  JOIN slik_checks   slik ON slik.customer_id = c.customer_id
    -- produk & limit
    LEFT  JOIN credit_limits cl  ON cl.customer_id = c.customer_id
    LEFT  JOIN loan_products lp  ON lp.product_id  = cl.product_id
    -- origination
    LEFT  JOIN loan_applications la ON la.customer_id = c.customer_id
    LEFT  JOIN credit_assessments ca ON ca.application_id = la.application_id
    LEFT  JOIN slik_checks slik2 ON slik2.slik_id = ca.slik_id      -- SLIK yang dipakai di assessment
    LEFT  JOIN loan_consents lcon ON lcon.application_id = la.application_id
    -- servicing
    LEFT  JOIN loans l           ON l.application_id = la.application_id
    LEFT  JOIN disbursements disb ON disb.loan_id = l.loan_id
    LEFT  JOIN repayment_schedules rs ON rs.loan_id = l.loan_id
    LEFT  JOIN payments p        ON p.loan_id = l.loan_id AND p.installment_id = rs.installment_id
    LEFT  JOIN transactions t    ON t.loan_id = l.loan_id AND t.customer_id = c.customer_id
    -- recovery (opsional)
    LEFT  JOIN loan_restructurings lr ON lr.loan_id = l.loan_id
    LEFT  JOIN collection_activities col ON col.loan_id = l.loan_id
    -- notifikasi
    LEFT  JOIN notifications n    ON n.customer_id = c.customer_id
    -- peran internal (ALIAS TERPISAH — beda orang dari borrower)
    LEFT  JOIN user_accounts approver ON approver.user_id = lr.approved_by
    LEFT  JOIN user_accounts officer  ON officer.user_id  = col.officer_id
    LEFT  JOIN user_roles ur ON ur.user_id = ua.user_id
    LEFT  JOIN roles r       ON r.role_id  = ur.role_id;
-- audit_logs: query TERPISAH, mis. WHERE entity_name='loans' AND entity_id=@loan_id