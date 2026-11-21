-- ================================================================
-- store_photos.sql — 판매점 사진 (사용자가 올리고 관리자가 승인한 것만 앱에 표시)
--   · 사진 파일: Storage 버킷 store-photos (공개 읽기 · 누구나 올리기만)
--   · 사진 목록: store_photos (앱은 승인된 것만 읽기 · 새 사진은 '승인 대기'로만 넣기)
--   · 승인 · 거절 · 대기 목록: 함수만 가능, 승인 키가 맞아야 동작 (키는 앱에 없음 — 아래 맨 끝에서 직접 정함)
-- 크롤링 테이블(lottery_stores 등)은 건드리지 않는다.
-- ================================================================

-- 1) 사진 보관함 (공개 읽기)
INSERT INTO storage.buckets (id, name, public)
VALUES ('store-photos', 'store-photos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS "store_photos_upload" ON storage.objects;
CREATE POLICY "store_photos_upload" ON storage.objects
  FOR INSERT TO anon, authenticated
  WITH CHECK (bucket_id = 'store-photos');

DROP POLICY IF EXISTS "store_photos_read" ON storage.objects;
CREATE POLICY "store_photos_read" ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (bucket_id = 'store-photos');

-- 2) 사진 목록
CREATE TABLE IF NOT EXISTS store_photos (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  dhlottery_code text       NOT NULL,
  store_name    text,
  path          text        NOT NULL,                      -- store-photos 버킷 안 경로
  status        text        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  source        text        NOT NULL DEFAULT 'user' CHECK (source IN ('user', 'admin')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  reviewed_at   timestamptz
);
CREATE INDEX IF NOT EXISTS store_photos_code_status ON store_photos (dhlottery_code, status);

ALTER TABLE store_photos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "store_photos_read_approved" ON store_photos;
CREATE POLICY "store_photos_read_approved" ON store_photos
  FOR SELECT TO anon, authenticated USING (status = 'approved');

DROP POLICY IF EXISTS "store_photos_insert_pending" ON store_photos;
CREATE POLICY "store_photos_insert_pending" ON store_photos
  FOR INSERT TO anon, authenticated
  WITH CHECK (status = 'pending' AND reviewed_at IS NULL);

REVOKE UPDATE, DELETE, TRUNCATE ON store_photos FROM anon, authenticated;
GRANT SELECT, INSERT ON store_photos TO anon, authenticated;
GRANT ALL ON store_photos TO service_role;

-- 3) 승인 키 (앱 anon 은 읽을 수 없음)
CREATE TABLE IF NOT EXISTS store_photo_admin (
  id  int  PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  key text NOT NULL
);
ALTER TABLE store_photo_admin ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON store_photo_admin FROM anon, authenticated;

-- 4) 함수 — 통계(누구나) · 목록/승인(키 필요)
CREATE OR REPLACE FUNCTION store_photo_counts()
RETURNS TABLE (status text, n bigint)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT status, count(*) FROM store_photos GROUP BY status;
$$;

CREATE OR REPLACE FUNCTION list_store_photos(p_key text, p_status text)
RETURNS SETOF store_photos
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM store_photo_admin WHERE key = p_key) THEN
    RAISE EXCEPTION '승인 키가 맞지 않습니다';
  END IF;
  RETURN QUERY SELECT * FROM store_photos WHERE status = p_status ORDER BY created_at DESC LIMIT 200;
END;
$$;

CREATE OR REPLACE FUNCTION review_store_photo(p_id uuid, p_status text, p_key text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM store_photo_admin WHERE key = p_key) THEN
    RAISE EXCEPTION '승인 키가 맞지 않습니다';
  END IF;
  IF p_status NOT IN ('pending', 'approved', 'rejected') THEN
    RAISE EXCEPTION '상태 값 오류';
  END IF;
  UPDATE store_photos SET status = p_status, reviewed_at = now() WHERE id = p_id;
END;
$$;

REVOKE ALL ON FUNCTION store_photo_counts() FROM public;
REVOKE ALL ON FUNCTION list_store_photos(text, text) FROM public;
REVOKE ALL ON FUNCTION review_store_photo(uuid, text, text) FROM public;
GRANT EXECUTE ON FUNCTION store_photo_counts() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION list_store_photos(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION review_store_photo(uuid, text, text) TO anon, authenticated;

-- 5) ★ 승인 키 정하기 — '여기에-승인키' 를 원하는 키로 바꿔서 실행 (앱 관리자 화면에서 한 번 입력)
INSERT INTO store_photo_admin (id, key) VALUES (1, '여기에-승인키')
ON CONFLICT (id) DO UPDATE SET key = EXCLUDED.key;

-- 확인
SELECT 'store_photos_table' AS check, (to_regclass('public.store_photos') IS NOT NULL)::text AS value
UNION ALL SELECT 'bucket', (SELECT count(*) FROM storage.buckets WHERE id = 'store-photos')::text
UNION ALL SELECT 'admin_key_set', (SELECT (key <> '여기에-승인키')::text FROM store_photo_admin WHERE id = 1);

-- 6) (추가 2026-11-21) 관리자 사진 삭제 — 목록에서 지움 (승인 키 필요). 보관함 파일은 남으니 필요하면 Supabase Storage 화면에서 정리
CREATE OR REPLACE FUNCTION delete_store_photo(p_id uuid, p_key text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM store_photo_admin WHERE key = p_key) THEN
    RAISE EXCEPTION '승인 키가 맞지 않습니다';
  END IF;
  DELETE FROM store_photos WHERE id = p_id;
END;
$$;
REVOKE ALL ON FUNCTION delete_store_photo(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION delete_store_photo(uuid, text) TO anon, authenticated;
