-- scope: full
-- authored.pss_sr_group_alias: AUTHORED, not source data. Three names the Public Spending Statistics use for a
-- Spending Review group that OSCAR writes differently. Every other PSS group name equals the OSCAR name
-- exactly. The table maps a name to a name: it holds no amount, and no real total is built from it (it only
-- decides which OSCAR group a PSS row is compared with). Register: docs/data-dictionary/annual-restated.md.

DROP TABLE IF EXISTS authored.pss_sr_group_alias;
GO

CREATE TABLE authored.pss_sr_group_alias (
    pss_sr_group_name   nvarchar(200) NOT NULL CONSTRAINT pk_authored_pss_sr_group_alias PRIMARY KEY,
    bud_sr_group_name   nvarchar(100) NOT NULL,
    reason              nvarchar(300) NOT NULL
);
GO

INSERT INTO authored.pss_sr_group_alias (pss_sr_group_name, bud_sr_group_name, reason)
VALUES
    (N'Scottish Government', N'Scotland', N'PSS names the devolved administration, OSCAR names the nation'),
    (N'Welsh Government', N'Wales', N'PSS names the devolved administration, OSCAR names the nation'),
    (N'Northern Ireland Executive', N'Northern Ireland', N'PSS names the devolved administration, OSCAR names the nation');
GO

EXEC sys.sp_addextendedproperty @name = N'MS_Description',
    @value = N'AUTHORED: three PSS to OSCAR Spending Review group name aliases. Holds no amounts; never part of a real total.',
    @level0type = N'SCHEMA', @level0name = N'authored', @level1type = N'TABLE', @level1name = N'pss_sr_group_alias';
GO
