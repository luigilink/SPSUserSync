function Get-SPSReportCardHtml {
    <#
        .SYNOPSIS
        Builds the HTML for one summary "card" (a big number plus a label).
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        $Value,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Label,

        [Parameter()]
        [ValidateSet('', 'warn')]
        [System.String]
        $Tone = ''
    )

    $encValue  = ConvertTo-SPSHtmlEncoded -Value ("$Value")
    $encLabel  = ConvertTo-SPSHtmlEncoded -Value $Label
    $toneClass = if ([string]::IsNullOrEmpty($Tone)) { '' } else { " $Tone" }
    return "<div class=`"card$toneClass`"><div class=`"card-value`">$encValue</div><div class=`"card-label`">$encLabel</div></div>"
}

function Get-SPSReportTopListHtml {
    <#
        .SYNOPSIS
        Builds the HTML for a "Top N" list rendered as a small two-column table.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Title,

        [Parameter()]
        [AllowNull()]
        $Groups
    )

    $rowsHtml = ''
    foreach ($group in $Groups) {
        $name = if ([string]::IsNullOrEmpty($group.Name)) { '(none)' } else { $group.Name }
        $encName = ConvertTo-SPSHtmlEncoded -Value $name
        $rowsHtml += "<tr><td>$encName</td><td style=`"text-align:right`">$($group.Count)</td></tr>"
    }
    if ([string]::IsNullOrEmpty($rowsHtml)) {
        $rowsHtml = '<tr><td colspan="2">No data</td></tr>'
    }

    $encTitle = ConvertTo-SPSHtmlEncoded -Value $Title
    return "<div class=`"list-box`"><h3>$encTitle</h3><table><tbody>$rowsHtml</tbody></table></div>"
}

function Get-SPSReportHtmlHead {
    <#
        .SYNOPSIS
        Returns the document head (with the embedded stylesheet) and the opening body tag.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Title
    )

    $css = @'
:root{--brand:#1f6fb2;--brand-dark:#155a91;--ink:#222;--muted:#666;--line:#e3e3e3;--warn-bg:rgb(255,248,225);--warn-border:rgb(193,156,0);--zebra:#f7f9fb}
*{box-sizing:border-box}
body{font-family:'Aptos','Segoe UI',-apple-system,BlinkMacSystemFont,sans-serif;color:var(--ink);margin:0;padding:24px;background:#fff}
h1{color:var(--brand);font-size:22px;margin:0 0 4px}
h2{color:var(--brand);font-size:16px;margin:24px 0 8px;border-bottom:2px solid var(--brand);padding-bottom:4px}
h3{color:var(--brand-dark);font-size:13px;margin:0 0 6px}
.meta{color:var(--muted);font-size:12px;margin-bottom:16px}
.summary{background:#eef5fb;border:1px solid #cfe0ef;border-left:4px solid var(--brand);border-radius:6px;padding:16px;margin-bottom:8px}
.cards{display:flex;flex-wrap:wrap;gap:12px}
.card{background:#fff;border:1px solid var(--line);border-radius:6px;padding:12px 16px;min-width:120px}
.card-value{font-size:24px;font-weight:700;color:var(--brand)}
.card-label{font-size:12px;color:var(--muted)}
.card.warn{background:var(--warn-bg);border-color:var(--warn-border)}
.card.warn .card-value{color:var(--warn-border)}
.lists{display:flex;flex-wrap:wrap;gap:16px;margin-top:12px}
.list-box{flex:1;min-width:240px}
table{border-collapse:collapse;width:100%;font-size:12px}
th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top}
th{background:var(--brand);color:#fff;cursor:pointer;user-select:none;position:sticky;top:0}
tbody tr:nth-child(even){background:var(--zebra)}
tbody tr.unresolved td{background:var(--warn-bg)}
tbody tr.unresolved td:first-child{border-left:3px solid var(--warn-border);font-weight:600}
.controls{display:flex;justify-content:space-between;align-items:center;margin:12px 0;flex-wrap:wrap;gap:8px}
.search{padding:6px 10px;border:1px solid var(--line);border-radius:4px;font-size:13px;width:280px;max-width:100%}
.pager{display:flex;gap:8px;align-items:center;font-size:12px}
.pager button{padding:4px 10px;border:1px solid var(--line);background:#fff;border-radius:4px;cursor:pointer}
.pager button:disabled{opacity:.4;cursor:default}
.note{background:var(--warn-bg);border:1px solid var(--warn-border);border-radius:6px;padding:10px 14px;font-size:12px;margin:8px 0}
.footer{color:var(--muted);font-size:11px;margin-top:24px;border-top:1px solid var(--line);padding-top:8px}
'@

    return "<!DOCTYPE html><html lang=`"en`"><head><meta charset=`"utf-8`"><meta name=`"viewport`" content=`"width=device-width, initial-scale=1`"><title>$Title</title><style>$css</style></head><body>"
}

function Get-SPSReportHtmlScript {
    <#
        .SYNOPSIS
        Returns the vanilla-JavaScript block that renders the interactive table.
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    $js = @'
(function(){
  var node = document.getElementById('spsReportData');
  var data = JSON.parse(node.textContent || node.innerText);
  var cols = data.columns || [];
  var rows = data.rows || [];
  var pageSize = 50, page = 1, sortField = null, sortDir = 1, view = rows;
  var search = document.getElementById('spsSearch');
  var thead = document.getElementById('spsThead');
  var tbody = document.getElementById('spsTbody');
  var info = document.getElementById('spsPageInfo');
  var prev = document.getElementById('spsPrev');
  var next = document.getElementById('spsNext');

  function buildHead(){
    var tr = document.createElement('tr');
    cols.forEach(function(c){
      var th = document.createElement('th');
      th.textContent = c.label + '  \u2195';
      th.addEventListener('click', function(){
        if (sortField === c.field) { sortDir = -sortDir; } else { sortField = c.field; sortDir = 1; }
        applySort(); render();
      });
      tr.appendChild(th);
    });
    thead.appendChild(tr);
  }
  function applyFilter(){
    var q = (search.value || '').trim().toLowerCase();
    if (!q) { view = rows; }
    else {
      view = rows.filter(function(r){
        return cols.some(function(c){
          var v = r[c.field];
          return v != null && String(v).toLowerCase().indexOf(q) !== -1;
        });
      });
    }
    page = 1;
  }
  function applySort(){
    if (!sortField) { return; }
    view = view.slice().sort(function(a,b){
      var x = a[sortField] == null ? '' : String(a[sortField]).toLowerCase();
      var y = b[sortField] == null ? '' : String(b[sortField]).toLowerCase();
      if (x < y) { return -1 * sortDir; }
      if (x > y) { return 1 * sortDir; }
      return 0;
    });
  }
  function render(){
    var totalPages = Math.max(1, Math.ceil(view.length / pageSize));
    if (page > totalPages) { page = totalPages; }
    var start = (page - 1) * pageSize;
    var slice = view.slice(start, start + pageSize);
    tbody.innerHTML = '';
    slice.forEach(function(r){
      var tr = document.createElement('tr');
      if (r._flag) { tr.className = r._flag; }
      cols.forEach(function(c){
        var td = document.createElement('td');
        td.textContent = r[c.field] == null ? '' : r[c.field];
        tr.appendChild(td);
      });
      tbody.appendChild(tr);
    });
    info.textContent = view.length + ' rows \u00b7 page ' + page + '/' + totalPages;
    prev.disabled = page <= 1;
    next.disabled = page >= totalPages;
  }
  search.addEventListener('input', function(){ applyFilter(); applySort(); render(); });
  prev.addEventListener('click', function(){ if (page > 1) { page--; render(); } });
  next.addEventListener('click', function(){ page++; render(); });
  buildHead(); render();
})();
'@

    return "<script>$js</script>"
}
