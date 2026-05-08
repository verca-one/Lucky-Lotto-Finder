-- 쿠폰 테이블
CREATE TABLE IF NOT EXISTS coupons (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  type TEXT NOT NULL DEFAULT 'ad_removal',
  is_active BOOLEAN DEFAULT true,
  max_uses INTEGER DEFAULT 1,
  used_count INTEGER DEFAULT 0,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 쿠폰 사용 기록 테이블
CREATE TABLE IF NOT EXISTS coupon_redemptions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  coupon_code TEXT NOT NULL REFERENCES coupons(code),
  device_id TEXT NOT NULL,
  redeemed_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(coupon_code, device_id)
);

-- 인덱스
CREATE INDEX IF NOT EXISTS idx_coupons_code ON coupons(code);
CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_device ON coupon_redemptions(device_id);
CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_code ON coupon_redemptions(coupon_code);

-- RLS (Row Level Security) - anon 키로 접근 가능하도록
ALTER TABLE coupons ENABLE ROW LEVEL SECURITY;
ALTER TABLE coupon_redemptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow read coupons" ON coupons FOR SELECT USING (true);
CREATE POLICY "Allow insert coupons" ON coupons FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow update coupons" ON coupons FOR UPDATE USING (true);

CREATE POLICY "Allow read redemptions" ON coupon_redemptions FOR SELECT USING (true);
CREATE POLICY "Allow insert redemptions" ON coupon_redemptions FOR INSERT WITH CHECK (true);
