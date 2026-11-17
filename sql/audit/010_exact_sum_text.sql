-- audit.exact_sum_text(whole, frac): the exact value whole + frac as plain text, with no exponent,
-- no trailing zeros and no "-0". It compares a sum of raw amounts (SUM(amount_whole) and
-- SUM(amount_frac)) with a control total written as text. whole and frac may have opposite signs
-- (5 and -0.3 is 4.7), and frac may exceed one in absolute value because it is a sum of fractions.
-- The work is done on integers and text: decimal arithmetic at 31 places would round.

DROP FUNCTION IF EXISTS audit.exact_sum_text;
GO

CREATE FUNCTION audit.exact_sum_text (@whole bigint, @frac decimal(38,31))
RETURNS varchar(100)
AS
BEGIN
    -- value = whole + s * (carry + 0.digits), where s is the sign of frac
    DECLARE @txt varchar(60) = CONVERT(varchar(60), @frac);        -- e.g. -12.6410417009665510197161520200381
    DECLARE @s int = CASE WHEN LEFT(@txt, 1) = '-' THEN -1 ELSE 1 END;
    DECLARE @unsigned varchar(60) = CASE WHEN @s = -1 THEN SUBSTRING(@txt, 2, 60) ELSE @txt END;
    DECLARE @dot int = CHARINDEX('.', @unsigned);
    DECLARE @carry bigint = CAST(LEFT(@unsigned, @dot - 1) AS bigint);
    DECLARE @f decimal(38,0) = CAST(SUBSTRING(@unsigned, @dot + 1, 31) AS decimal(38,0));   -- 0.digits in units of 1e-31
    DECLARE @unit decimal(38,0) = CAST('10000000000000000000000000000000' AS decimal(38,0)); -- 1e31
    DECLARE @w bigint = @whole + @s * @carry;                      -- whole part with the carry folded in
    DECLARE @neg bit;
    DECLARE @mag bigint;                                           -- magnitude of the whole part

    IF @f = 0
    BEGIN
        SET @neg = CASE WHEN @w < 0 THEN 1 ELSE 0 END;
        SET @mag = ABS(@w);
    END
    ELSE IF @s = 1 AND @w >= 0
    BEGIN
        SET @neg = 0;  SET @mag = @w;
    END
    ELSE IF @s = 1                                                 -- w < 0, fraction adds: -(|w| - 1) - (1 - f)
    BEGIN
        SET @neg = 1;  SET @mag = -@w - 1;  SET @f = @unit - @f;
    END
    ELSE IF @w <= 0                                                -- s = -1: both pull below zero
    BEGIN
        SET @neg = 1;  SET @mag = -@w;
    END
    ELSE                                                           -- s = -1, w > 0: (w - 1) + (1 - f)
    BEGIN
        SET @neg = 0;  SET @mag = @w - 1;  SET @f = @unit - @f;
    END;

    DECLARE @fd varchar(40) = RIGHT(REPLICATE('0', 31) + CAST(@f AS varchar(40)), 31);
    DECLARE @trimmed varchar(40) = LEFT(@fd, LEN(@fd) - PATINDEX('%[^0]%', REVERSE(@fd)) + 1);
    RETURN CASE WHEN @neg = 1 THEN '-' ELSE '' END
         + CAST(@mag AS varchar(30))
         + CASE WHEN @f = 0 THEN '' ELSE '.' + @trimmed END;
END;
GO
