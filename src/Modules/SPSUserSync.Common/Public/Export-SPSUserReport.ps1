function Export-SPSUserReport {
    <#
        .SYNOPSIS
        Generates a self-contained HTML report from an SPSUserSync JSON dataset.

        .DESCRIPTION
        Export-SPSUserReport produces a single, dependency-free HTML file (no CDN,
        works offline) summarizing one of the two SPSUserSync datasets:

        - ReportType 'UserInfoList' : the snapshot written by SPSyncUserInfoList.ps1
          (UserLogin / DisplayName / Email / Country ...). The summary shows the total
          user count, the email coverage, and the top countries and Active Directory
          domains.
        - ReportType 'UserProfile' : the reconciliation log written by
          SPSyncUserProfile.ps1 (AccountName / Status / WorkEmail / Date). The summary
          breaks the run down by Status (CREATE / UPDATE / INFO / UNKNOWN_USER).

        The full dataset is embedded in the page as JSON and rendered by a small
        vanilla-JavaScript table with live search, column sorting and pagination. All
        values are HTML-encoded and rendered through textContent, so AD-sourced names
        and emails cannot break the page or inject markup.

        The data can be supplied either as a file (-InputFile, a JSON snapshot) or as an
        in-memory object array (-InputObject).

        Returns the path of the report that was written.

        .PARAMETER InputFile
        Path of a JSON file to read the records from.

        .PARAMETER InputObject
        In-memory array of records to report on.

        .PARAMETER ReportType
        'UserInfoList' or 'UserProfile' - drives the summary cards and table columns.

        .PARAMETER OutputFile
        Destination path of the generated .html file.

        .PARAMETER Title
        Heading shown at the top of the report. Defaults to a per-type title.

        .PARAMETER EnvName
        Environment label shown in the metadata line (e.g. PROD).

        .PARAMETER AppCode
        Application code shown in the metadata line.

        .PARAMETER ClaimPrefix
        Claim prefix stripped from UserLogin when computing the top AD domains
        (UserInfoList only). Defaults to 'i:0#.w|'.

        .PARAMETER Version
        SPSUserSync version stamped in the report footer. Defaults to the module version.

        .EXAMPLE
        Export-SPSUserReport -InputFile $json -ReportType 'UserInfoList' -OutputFile $html -EnvName 'PROD' -AppCode 'CONTOSO'

        .EXAMPLE
        Export-SPSUserReport -InputObject $results -ReportType 'UserProfile' -OutputFile $html
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByFile')]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true, ParameterSetName = 'ByFile')]
        [System.String]
        $InputFile,

        [Parameter(Mandatory = $true, ParameterSetName = 'ByObject')]
        [AllowEmptyCollection()]
        [System.Object[]]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateSet('UserInfoList', 'UserProfile')]
        [System.String]
        $ReportType,

        [Parameter(Mandatory = $true)]
        [System.String]
        $OutputFile,

        [Parameter()]
        [System.String]
        $Title,

        [Parameter()]
        [System.String]
        $EnvName,

        [Parameter()]
        [System.String]
        $AppCode,

        [Parameter()]
        [System.String]
        $ClaimPrefix = 'i:0#.w|',

        [Parameter()]
        [System.String]
        $Version
    )

    # ---- Load records -------------------------------------------------------------
    if ($PSCmdlet.ParameterSetName -eq 'ByFile') {
        if (-not (Test-Path -Path $InputFile)) {
            throw "Export-SPSUserReport: input file not found: $InputFile"
        }
        $raw = Get-Content -Path $InputFile -Raw -Encoding UTF8
        $records = if ([string]::IsNullOrWhiteSpace($raw)) { @() } else { @($raw | ConvertFrom-Json) }
    }
    else {
        $records = @($InputObject)
    }

    if ([string]::IsNullOrEmpty($Version)) {
        $moduleVersion = (Get-Module -Name SPSUserSync.Common -ErrorAction SilentlyContinue).Version
        $Version = if ($null -ne $moduleVersion) { $moduleVersion.ToString() } else { 'unknown' }
    }

    # ---- Per-type configuration ---------------------------------------------------
    # Per-row flag (keyed by record index) used to highlight problem rows in the
    # table, and an optional legend shown above the table when any row is flagged.
    $flagByIndex = @{}
    $detailsNote = ''

    if ($ReportType -eq 'UserInfoList') {
        if ([string]::IsNullOrEmpty($Title)) { $Title = 'SPSUserSync - User Information List Report' }
        $columns = @(
            @{ field = 'UserLogin';   label = 'User Login' }
            @{ field = 'DisplayName'; label = 'Display Name' }
            @{ field = 'Email';       label = 'Email' }
            @{ field = 'Country';     label = 'Country' }
        )

        $total        = $records.Count
        $withEmail    = @($records | Where-Object { -not [string]::IsNullOrEmpty($_.Email) }).Count
        $withoutEmail = $total - $withEmail

        # Flag users whose identity did not resolve from AD. A record is
        # "unresolved" when it has no display name, or its display name is just
        # the de-claimed login (the signature of a failed Set-SPUser -SyncFromAD:
        # the script fell back to the SharePoint login as the display name).
        # These rows will not sync to the user profile and are the ones
        # Remove-SPUser would prune when RemoveUnresolvableUsers is enabled.
        $unresolvedCount = 0
        for ($i = 0; $i -lt $records.Count; $i++) {
            $display   = "$($records[$i].DisplayName)".Trim()
            $declaimed = "$($records[$i].UserLogin)"
            if (-not [string]::IsNullOrEmpty($ClaimPrefix) -and $declaimed.StartsWith($ClaimPrefix)) {
                $declaimed = $declaimed.Substring($ClaimPrefix.Length)
            }
            if ([string]::IsNullOrEmpty($display) -or $display.Equals($declaimed, [System.StringComparison]::OrdinalIgnoreCase)) {
                $flagByIndex[$i] = 'unresolved'
                $unresolvedCount++
            }
        }

        $topCountries = $records |
            Where-Object { -not [string]::IsNullOrEmpty($_.Country) } |
            Group-Object -Property Country | Sort-Object Count -Descending | Select-Object -First 10

        $domainNames = foreach ($record in $records) {
            $parsed = ConvertFrom-SPSUserLogin -UserLogin $record.UserLogin -ClaimPrefix $ClaimPrefix
            if ($parsed.IsValid) { $parsed.Domain }
        }
        $topDomains = $domainNames | Group-Object | Sort-Object Count -Descending | Select-Object -First 10

        $cardsHtml = @(
            (Get-SPSReportCardHtml -Value $total -Label 'Total users')
            (Get-SPSReportCardHtml -Value $withEmail -Label 'With email')
            (Get-SPSReportCardHtml -Value $withoutEmail -Label 'Without email')
            (Get-SPSReportCardHtml -Value $unresolvedCount -Label 'Unresolved' -Tone $(if ($unresolvedCount -gt 0) { 'warn' } else { '' }))
        ) -join ''

        if ($unresolvedCount -gt 0) {
            $userWord = if ($unresolvedCount -eq 1) { 'user' } else { 'users' }
            $detailsNote = "<div class=`"note`"><strong>$unresolvedCount unresolved $userWord</strong> highlighted below &mdash; their identity did not resolve from Active Directory (no display name, or the display name is just the login), so they will not sync to the user profile and would be removed if <code>RemoveUnresolvableUsers</code> is enabled.</div>"
        }

        $listsHtml = (Get-SPSReportTopListHtml -Title 'Top countries' -Groups $topCountries) +
                     (Get-SPSReportTopListHtml -Title 'Top AD domains' -Groups $topDomains)
        $summaryInner = "<div class=`"cards`">$cardsHtml</div><div class=`"lists`">$listsHtml</div>"
    }
    else {
        if ([string]::IsNullOrEmpty($Title)) { $Title = 'SPSUserSync - User Profile Reconciliation Report' }
        $columns = @(
            @{ field = 'AccountName'; label = 'Account Name' }
            @{ field = 'Status';      label = 'Status' }
            @{ field = 'WorkEmail';   label = 'Work Email' }
            @{ field = 'Date';        label = 'Date' }
        )

        $total    = $records.Count
        $byStatus = $records | Group-Object -Property Status | Sort-Object Count -Descending

        # Highlight rows that could not be matched to a profile (UNKNOWN_USER).
        $unknownCount = 0
        for ($i = 0; $i -lt $records.Count; $i++) {
            if ("$($records[$i].Status)" -eq 'UNKNOWN_USER') {
                $flagByIndex[$i] = 'unresolved'
                $unknownCount++
            }
        }
        if ($unknownCount -gt 0) {
            $userWord = if ($unknownCount -eq 1) { 'account' } else { 'accounts' }
            $detailsNote = "<div class=`"note`"><strong>$unknownCount UNKNOWN_USER $userWord</strong> highlighted below &mdash; these were present in the snapshot but could not be matched to a user profile.</div>"
        }

        $cards = @( (Get-SPSReportCardHtml -Value $total -Label 'Total processed') )
        foreach ($group in $byStatus) {
            $statusLabel = if ([string]::IsNullOrEmpty($group.Name)) { '(none)' } else { $group.Name }
            $cardTone    = if ($group.Name -eq 'UNKNOWN_USER') { 'warn' } else { '' }
            $cards += (Get-SPSReportCardHtml -Value $group.Count -Label $statusLabel -Tone $cardTone)
        }
        $summaryInner = "<div class=`"cards`">$($cards -join '')</div>"
    }

    # ---- Build the embedded data payload -----------------------------------------
    $rows = for ($i = 0; $i -lt $records.Count; $i++) {
        $record = $records[$i]
        $row = [ordered]@{}
        foreach ($column in $columns) {
            $row[$column.field] = "$($record.($column.field))"
        }
        if ($flagByIndex.ContainsKey($i)) {
            $row['_flag'] = $flagByIndex[$i]
        }
        [PSCustomObject]$row
    }
    $payload = [ordered]@{
        columns = $columns
        rows    = @($rows)
    }
    $json = $payload | ConvertTo-Json -Depth 5 -Compress
    # Neutralize any sequence that could break out of the <script> block
    $json = $json -replace '<', '\u003c' -replace '>', '\u003e' -replace '&', '\u0026'

    # ---- Encode the metadata ------------------------------------------------------
    $encTitle   = ConvertTo-SPSHtmlEncoded -Value $Title
    $encEnv     = ConvertTo-SPSHtmlEncoded -Value $EnvName
    $encApp     = ConvertTo-SPSHtmlEncoded -Value $AppCode
    $encVersion = ConvertTo-SPSHtmlEncoded -Value $Version
    $generated  = Get-Date -Format 'yyyy-MM-dd HH:mm'

    $metaParts = @()
    if (-not [string]::IsNullOrEmpty($encEnv)) { $metaParts += "Environment: $encEnv" }
    if (-not [string]::IsNullOrEmpty($encApp)) { $metaParts += "AppCode: $encApp" }
    $metaParts += "Generated: $generated"
    $metaParts += "SPSUserSync $encVersion"
    $metaLine = $metaParts -join ' &middot; '

    # ---- Assemble the document ----------------------------------------------------
    $html = (Get-SPSReportHtmlHead -Title $encTitle) +
            "<h1>$encTitle</h1>" +
            "<div class=`"meta`">$metaLine</div>" +
            "<div class=`"summary`"><h3 style=`"margin-top:0`">Summary</h3>$summaryInner</div>" +
            '<h2>Details</h2>' +
            $detailsNote +
            '<div class="controls"><input id="spsSearch" class="search" placeholder="Filter rows..."><div class="pager"><button id="spsPrev">Prev</button><span id="spsPageInfo"></span><button id="spsNext">Next</button></div></div>' +
            '<table><thead id="spsThead"></thead><tbody id="spsTbody"></tbody></table>' +
            "<div class=`"footer`">Generated by SPSUserSync $encVersion. This report contains personal data (names, email addresses) &mdash; handle and store it accordingly.</div>" +
            "<script type=`"application/json`" id=`"spsReportData`">$json</script>" +
            (Get-SPSReportHtmlScript) +
            '</body></html>'

    $outDir = Split-Path -Path $OutputFile -Parent
    if (-not [string]::IsNullOrEmpty($outDir) -and -not (Test-Path -Path $outDir)) {
        $null = New-Item -Path $outDir -ItemType Directory -Force
    }
    Set-Content -Path $OutputFile -Value $html -Force -Encoding UTF8

    return $OutputFile
}
