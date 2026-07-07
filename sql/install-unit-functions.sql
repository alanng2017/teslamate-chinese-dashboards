CREATE OR REPLACE FUNCTION public.convert_celsius(n numeric, unit text)
 RETURNS numeric
 LANGUAGE sql
AS $function$
  SELECT
  CASE $2 WHEN 'C' THEN $1
          WHEN 'F' THEN ($1 * 9 / 5) + 32
  END;
$function$;


CREATE OR REPLACE FUNCTION public.convert_km(n numeric, unit text)
 RETURNS numeric
 LANGUAGE sql
AS $function$
  SELECT
  CASE $2 WHEN 'km' THEN $1
          WHEN 'mi' THEN $1 / 1.60934
  END;
$function$;


CREATE OR REPLACE FUNCTION public.convert_m(n double precision, unit text)
 RETURNS double precision
 LANGUAGE sql
 IMMUTABLE STRICT
AS $function$
  SELECT
    CASE WHEN $2 = 'm' THEN $1
         WHEN $2 = 'ft' THEN $1 * 3.28084
    END;
$function$;


CREATE OR REPLACE FUNCTION public.convert_tire_pressure(n numeric, unit text)
 RETURNS numeric
 LANGUAGE sql
AS $function$
  SELECT
  CASE $2 WHEN 'bar' THEN $1
          WHEN 'psi' THEN $1 * 14.503773773
          WHEN 'kPa' THEN $1 * 100
          WHEN 'kpa' THEN $1 * 100
  END;
$function$;
