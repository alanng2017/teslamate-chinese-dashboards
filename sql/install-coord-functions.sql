-- ============================================================================
-- TeslaMate 中文仪表盘：地图坐标转换函数
--
-- 配合 v1.4.2+「地图源」下拉框使用。当用户在仪表盘选中 GCJ-02 系地图
-- (高德 / Google 路网) 时，自动把 TeslaMate 存储的 WGS-84 (GPS 原始)
-- 坐标转为 GCJ-02，让车辆轨迹与瓦片对齐；选中 OSM/Carto/Google 卫星时
-- 直接返回原值。
--
-- 安装：
--   docker exec -i teslamate-database-1 psql -U teslamate teslamate \
--     < sql/install-coord-functions.sql
--
-- 卸载：
--   DROP FUNCTION IF EXISTS lat_for_map(TEXT, DOUBLE PRECISION, DOUBLE PRECISION);
--   DROP FUNCTION IF EXISTS lng_for_map(TEXT, DOUBLE PRECISION, DOUBLE PRECISION);
--   DROP FUNCTION IF EXISTS wgs84_to_gcj02_lat(DOUBLE PRECISION, DOUBLE PRECISION);
--   DROP FUNCTION IF EXISTS wgs84_to_gcj02_lng(DOUBLE PRECISION, DOUBLE PRECISION);
--   DROP FUNCTION IF EXISTS is_outside_china(DOUBLE PRECISION, DOUBLE PRECISION);
--
-- 算法：eviltransform 标准 (https://github.com/googollee/eviltransform)
-- 精度：中国境内 < 0.5m；境外原样返回
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 先 DROP 旧版本（CREATE OR REPLACE 不允许改参数名/类型，纯升级路径需要这一步）
-- IF EXISTS 在全新安装时无副作用
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS lat_for_map(TEXT, DOUBLE PRECISION, DOUBLE PRECISION);
DROP FUNCTION IF EXISTS lng_for_map(TEXT, DOUBLE PRECISION, DOUBLE PRECISION);

-- ----------------------------------------------------------------------------
-- 内部辅助：判断坐标是否在 eviltransform 定义的中国境内 bbox 之外
-- 边界值来自 eviltransform 标准实现（约略覆盖大陆+港澳台）
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_outside_china(lat DOUBLE PRECISION, lng DOUBLE PRECISION)
RETURNS BOOLEAN AS $$
  -- 西经界 72.004 / 东经界 137.8347 / 南纬界 0.8293 / 北纬界 55.8271
  SELECT lng < 72.004 OR lng > 137.8347 OR lat < 0.8293 OR lat > 55.8271;
$$ LANGUAGE sql IMMUTABLE PARALLEL SAFE;

-- ----------------------------------------------------------------------------
-- 核心算法：WGS-84 → GCJ-02
-- 用 PL/pgSQL 是为了用本地变量缓存 sqrt_magic 等中间量，避免重复 sqrt 计算
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION wgs84_to_gcj02_lat(wgs_lat DOUBLE PRECISION, wgs_lng DOUBLE PRECISION)
RETURNS DOUBLE PRECISION AS $$
DECLARE
  a   CONSTANT DOUBLE PRECISION := 6378245.0;
  ee  CONSTANT DOUBLE PRECISION := 0.00669342162296594323;
  x   DOUBLE PRECISION;
  y   DOUBLE PRECISION;
  d_lat       DOUBLE PRECISION;
  rad_lat     DOUBLE PRECISION;
  magic       DOUBLE PRECISION;
  sqrt_magic  DOUBLE PRECISION;
BEGIN
  IF wgs_lat IS NULL OR wgs_lng IS NULL THEN
    RETURN NULL;
  END IF;
  IF is_outside_china(wgs_lat, wgs_lng) THEN
    RETURN wgs_lat;
  END IF;
  x := wgs_lng - 105.0;
  y := wgs_lat - 35.0;
  d_lat := -100.0 + 2.0*x + 3.0*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x));
  d_lat := d_lat + (20.0*sin(6.0*x*pi()) + 20.0*sin(2.0*x*pi())) * 2.0/3.0;
  d_lat := d_lat + (20.0*sin(y*pi()) + 40.0*sin(y/3.0*pi())) * 2.0/3.0;
  d_lat := d_lat + (160.0*sin(y/12.0*pi()) + 320.0*sin(y*pi()/30.0)) * 2.0/3.0;
  rad_lat := wgs_lat / 180.0 * pi();
  magic := sin(rad_lat);
  magic := 1 - ee * magic * magic;
  sqrt_magic := sqrt(magic);
  d_lat := (d_lat * 180.0) / ((a * (1 - ee)) / (magic * sqrt_magic) * pi());
  RETURN wgs_lat + d_lat;
END;
$$ LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION wgs84_to_gcj02_lng(wgs_lat DOUBLE PRECISION, wgs_lng DOUBLE PRECISION)
RETURNS DOUBLE PRECISION AS $$
DECLARE
  a   CONSTANT DOUBLE PRECISION := 6378245.0;
  ee  CONSTANT DOUBLE PRECISION := 0.00669342162296594323;
  x   DOUBLE PRECISION;
  y   DOUBLE PRECISION;
  d_lng       DOUBLE PRECISION;
  rad_lat     DOUBLE PRECISION;
  magic       DOUBLE PRECISION;
  sqrt_magic  DOUBLE PRECISION;
BEGIN
  IF wgs_lat IS NULL OR wgs_lng IS NULL THEN
    RETURN NULL;
  END IF;
  IF is_outside_china(wgs_lat, wgs_lng) THEN
    RETURN wgs_lng;
  END IF;
  x := wgs_lng - 105.0;
  y := wgs_lat - 35.0;
  d_lng := 300.0 + x + 2.0*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x));
  d_lng := d_lng + (20.0*sin(6.0*x*pi()) + 20.0*sin(2.0*x*pi())) * 2.0/3.0;
  d_lng := d_lng + (20.0*sin(x*pi()) + 40.0*sin(x/3.0*pi())) * 2.0/3.0;
  d_lng := d_lng + (150.0*sin(x/12.0*pi()) + 300.0*sin(x*pi()/30.0)) * 2.0/3.0;
  rad_lat := wgs_lat / 180.0 * pi();
  magic := sin(rad_lat);
  magic := 1 - ee * magic * magic;
  sqrt_magic := sqrt(magic);
  d_lng := (d_lng * 180.0) / (a / sqrt_magic * cos(rad_lat) * pi());
  RETURN wgs_lng + d_lng;
END;
$$ LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE;

-- ----------------------------------------------------------------------------
-- 包装函数：URL 含 autonavi 或 google.com（且不是 lyrs=s 卫星）→ 转 GCJ-02
-- LANGUAGE sql 让规划器内联到查询，省掉 PL/pgSQL 调用开销（trip 这种聚合后
-- 调用 N 次的面板，5~10x 性能提升）。
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION lat_for_map(map_url TEXT, wgs_lat DOUBLE PRECISION, wgs_lng DOUBLE PRECISION)
RETURNS DOUBLE PRECISION AS $$
  SELECT CASE
    WHEN map_url ILIKE '%autonavi%'
      OR (map_url ILIKE '%google.com%' AND map_url NOT ILIKE '%lyrs=s%')
    THEN wgs84_to_gcj02_lat(wgs_lat, wgs_lng)
    ELSE wgs_lat
  END;
$$ LANGUAGE sql IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION lng_for_map(map_url TEXT, wgs_lat DOUBLE PRECISION, wgs_lng DOUBLE PRECISION)
RETURNS DOUBLE PRECISION AS $$
  SELECT CASE
    WHEN map_url ILIKE '%autonavi%'
      OR (map_url ILIKE '%google.com%' AND map_url NOT ILIKE '%lyrs=s%')
    THEN wgs84_to_gcj02_lng(wgs_lat, wgs_lng)
    ELSE wgs_lng
  END;
$$ LANGUAGE sql IMMUTABLE PARALLEL SAFE;

-- ----------------------------------------------------------------------------
-- 自检：北京天安门 WGS-84 (39.913818, 116.397828) → GCJ-02 (39.91522, 116.40407)
-- 算法精度声称中国境内 < 0.5m，0.00001 度 ≈ 1.1m，足以捕获算法被改坏的情况。
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  test_lat DOUBLE PRECISION;
  test_lng DOUBLE PRECISION;
  expect_lat CONSTANT DOUBLE PRECISION := 39.91522;
  expect_lng CONSTANT DOUBLE PRECISION := 116.40407;
  tolerance  CONSTANT DOUBLE PRECISION := 0.00001;  -- ~1.1m
BEGIN
  test_lat := wgs84_to_gcj02_lat(39.913818, 116.397828);
  test_lng := wgs84_to_gcj02_lng(39.913818, 116.397828);
  IF abs(test_lat - expect_lat) > tolerance OR abs(test_lng - expect_lng) > tolerance THEN
    RAISE WARNING '坐标转换函数自检异常: 期望 (%, %), 实际 (%, %), 偏差 (%, %)',
      expect_lat, expect_lng, test_lat, test_lng,
      abs(test_lat - expect_lat), abs(test_lng - expect_lng);
  ELSE
    RAISE NOTICE '坐标转换函数安装成功 (天安门测试通过): (%, %)',
      round(test_lat::numeric, 5), round(test_lng::numeric, 5);
  END IF;
END $$;
