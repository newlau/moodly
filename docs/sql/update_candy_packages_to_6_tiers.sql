-- Moodly candy packages: switch to the 6 / 18 / 38 / 128 four-tier plan
-- Historical filename note: this script used to target 6 tiers; keep the file
-- in place so existing references do not break.
-- First-recharge bonus target:
--   ¥6: +0%
--   ¥18: +50%
--   ¥38: +100%
--   ¥128: +120%
--
-- NOTE: candy_packages has no bonus percentage column. The service-side
-- calculateCandyRechargeBonus logic must match the target percentages before
-- this data change is deployed.
--
-- IMPORTANT:
-- Old iOS builds only know the previous Product IDs. Server-side version
-- fallback must remain enabled before this script is applied in production:
--   iOS x-app-version < 1.0.4 or missing => old 6 tiers
--   iOS x-app-version >= 1.0.4 / Android => new 4 tiers
-- Do not delete old App Store Connect candy products until iOS 1.0.4 coverage is sufficient.

BEGIN;

UPDATE candy_packages
SET is_active = false
WHERE package_id IN (
  'candy_300',
  'candy_100',
  'candy_800',
  'candy_2500',
  'candy_3500',
  'candy_8800',
  'candy_9800',
  'candy_12000',
  'candy_16800',
  'candy_19800'
);

INSERT INTO candy_packages (
  package_id,
  candy_amount,
  price_cny,
  apple_product_id,
  tag,
  tag_visible,
  is_popular,
  sort,
  is_active
) VALUES
  ('candy_600', 600, 6.00, 'bubbly.candy.600', NULL, false, false, 1, true),
  ('candy_1800', 1800, 18.00, 'bubbly.candy.1800', '首充多赠900糖果', true, false, 2, true),
  ('candy_3800', 3800, 38.00, 'bubbly.candy.3800', '首充多赠3800糖果', true, true, 3, true),
  ('candy_12800', 12800, 128.00, 'bubbly.candy.12800', '首充多赠15360糖果', true, false, 4, true)
ON DUPLICATE KEY UPDATE
  candy_amount = VALUES(candy_amount),
  price_cny = VALUES(price_cny),
  apple_product_id = VALUES(apple_product_id),
  tag = VALUES(tag),
  tag_visible = VALUES(tag_visible),
  is_popular = VALUES(is_popular),
  sort = VALUES(sort),
  is_active = VALUES(is_active);

COMMIT;
