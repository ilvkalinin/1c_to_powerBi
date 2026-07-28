let
    Источник = Odbc.Query(
        "Driver={PostgreSQL Unicode};Server=virt207.worldclass.nnov.ru; Database=gymdb_test;Timeout=300;Fetch=10000;UseDeclareFetch=1;",
        "SELECT
            cast(_Reference59._Code as varchar(1000)) as КодКонтракта,
            count(*) as ""Количество посещений""
        FROM _AccumRg7575
        LEFT JOIN _Document325
            ON _AccumRg7575._RecorderRRef = _Document325._IDRRef
        LEFT JOIN _Reference132
            ON _Fld7577RRef = _Reference132._IDRRef
        LEFT JOIN _Reference141X1
            ON _Document325._Fld4171RRef = _Reference141X1._IDRRef
        LEFT JOIN _Reference59
            ON _AccumRg7575._Fld7578_RRRef = _Reference59._IDRRef
        WHERE
            _Document325._Fld4164RRef =
                decode('9a5a4c90d2b1aede4b91dcd1abe84c43', 'hex')
            AND cast(_Reference132._Description as varchar(1000))
                NOT IN ('Детский развивающий центр', 'Управляющая компания')
            AND _AccumRg7575._Period >= timestamp '2026-01-01'
            AND _AccumRg7575._Period < timestamp '2027-01-01'
            AND _Reference141X1._Fld1532RRef =
                decode('9e8eaa7b2e77c19f4a1c22a8d9c3efa1', 'hex')
            AND cast(_Reference59._Code as varchar(1000)) IS NOT NULL
        GROUP BY cast(_Reference59._Code as varchar(1000))"
    )
in
    Источник
