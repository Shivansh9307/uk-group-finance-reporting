-- test: department periods run forwards, do not overlap within a number, and have a known member type
SELECT p.department_number, p.valid_from_seq, p.valid_to_seq, 'bad range or type' AS problem
FROM stg.department_period AS p
WHERE p.valid_from_seq > p.valid_to_seq OR p.member_type NOT IN ('Department', 'Unallocated')
UNION ALL
SELECT a.department_number, a.valid_from_seq, a.valid_to_seq, 'overlaps another period'
FROM stg.department_period AS a
JOIN stg.department_period AS b
  ON b.department_number = a.department_number AND b.valid_from_seq > a.valid_from_seq AND b.valid_from_seq <= a.valid_to_seq;
