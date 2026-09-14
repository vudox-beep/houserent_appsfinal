-- Driver identity verification (licence OR NRC front + back).
-- Run once in phpMyAdmin against the HouseRent database.
--
-- identity_verified:
--   0 = not verified / pending review (default)
--   1 = verified (can go online + unlock jobs)
--   2 = rejected (must re-upload)

-- If a column already exists, skip that line and continue with the rest.
ALTER TABLE drivers
  ADD COLUMN identity_verified TINYINT NOT NULL DEFAULT 0
    COMMENT '0=unverified/pending, 1=verified, 2=rejected' AFTER booking_tokens;
ALTER TABLE drivers
  ADD COLUMN identity_doc_type VARCHAR(20) NULL
    COMMENT 'licence | nrc' AFTER identity_verified;
ALTER TABLE drivers
  ADD COLUMN licence_photo_url VARCHAR(500) NULL AFTER identity_doc_type;
ALTER TABLE drivers
  ADD COLUMN nrc_front_url VARCHAR(500) NULL AFTER licence_photo_url;
ALTER TABLE drivers
  ADD COLUMN nrc_back_url VARCHAR(500) NULL AFTER nrc_front_url;
ALTER TABLE drivers
  ADD COLUMN identity_submitted_at DATETIME NULL AFTER nrc_back_url;
ALTER TABLE drivers
  ADD COLUMN identity_reviewed_at DATETIME NULL AFTER identity_submitted_at;

-- Manual approve example:
-- UPDATE drivers SET identity_verified = 1, identity_reviewed_at = NOW() WHERE user_id = 920;
--
-- Reject example:
-- UPDATE drivers SET identity_verified = 2, identity_reviewed_at = NOW() WHERE user_id = 920;
