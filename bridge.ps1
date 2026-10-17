$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function Point3($value) {
    if ($null -eq $value -or $value.Count -lt 2 -or $value.Count -gt 3) { throw 'A point must have 2 or 3 coordinates.' }
    $p = [double[]]@(0,0,0)
    for ($i=0; $i -lt $value.Count; $i++) {
        $p[$i] = [double]$value[$i]
        if ([double]::IsNaN($p[$i]) -or [double]::IsInfinity($p[$i])) { throw 'Coordinates must be finite.' }
    }
    return ,$p
}
function Positive($value) {
    $v = [double]$value
    if ($v -le 0 -or [double]::IsInfinity($v) -or [double]::IsNaN($v)) { throw 'Size must be positive and finite.' }
    return $v
}
function LayerName($value) {
    if ([string]::IsNullOrWhiteSpace($value) -or $value.Length -gt 255 -or $value -match '[<>/\\":;?*|=,]') { throw 'Invalid layer/block name.' }
}
function CheckEntity($e) {
    if ($e.layer) { LayerName $e.layer }
    if ($e.linetype_scale) { $null=Positive $e.linetype_scale }
    switch ($e.type) {
        'line' { $null=Point3 $e.start; $null=Point3 $e.end }
        'circle' { $null=Point3 $e.center; $null=Positive $e.radius }
        'rectangle' { $null=Point3 $e.origin; $null=Positive $e.width; $null=Positive $e.height }
        'polyline' {
            if ($e.points.Count -lt 2 -or $e.points.Count -gt 2000) { throw 'Polyline needs 2 to 2000 points.' }
            foreach ($p in $e.points) { if ($p.Count -ne 2) { throw 'Polyline points must be XY pairs.' }; $null=Point3 $p }
        }
        'text' { $null=Point3 $e.position; $null=Positive $e.height; if ([string]::IsNullOrEmpty($e.text) -or $e.text.Length -gt 2000) { throw 'Text needs 1 to 2000 characters.' } }
        'dimension' { $null=Point3 $e.start; $null=Point3 $e.end; $null=Point3 $e.position; if ($e.text_height) { $null=Positive $e.text_height } }
        'block' { LayerName $e.name; $null=Point3 $e.position; if ($e.scale) { $null=Positive $e.scale } }
        'filled_circle' { if ($e.center.Count -ne 2) { throw 'Filled circle center must be an XY pair.' }; $null=Point3 $e.center; $null=Positive $e.radius }
        'filled_polygon' {
            if ($e.points.Count -lt 3 -or $e.points.Count -gt 4) { throw 'Filled polygon needs 3 or 4 points.' }
            foreach ($p in $e.points) { if ($p.Count -ne 2) { throw 'Filled polygon points must be XY pairs.' }; $null=Point3 $p }
        }
        default { throw "Unsupported entity type: $($e.type)" }
    }
}
function AddEntity($container, $e, $doc) {
    switch ($e.type) {
        'line' { $o=$container.AddLine((Point3 $e.start),(Point3 $e.end)) }
        'circle' { $o=$container.AddCircle((Point3 $e.center),[double]$e.radius) }
        'rectangle' {
            $p=Point3 $e.origin; $x=$p[0]; $y=$p[1]; $w=[double]$e.width; $h=[double]$e.height
            $o=$container.AddLightWeightPolyline([double[]]@($x,$y,($x+$w),$y,($x+$w),($y+$h),$x,($y+$h)))
            $o.Closed=$true; $o.Elevation=$p[2]
        }
        'polyline' {
            $xy=New-Object 'System.Collections.Generic.List[double]'
            foreach ($p in $e.points) { $xy.Add([double]$p[0]); $xy.Add([double]$p[1]) }
            $o=$container.AddLightWeightPolyline($xy.ToArray()); $o.Closed=[bool]$e.closed; $o.Elevation=0.0
        }
        'text' { $o=$container.AddText([string]$e.text,(Point3 $e.position),[double]$e.height) }
        'dimension' {
            $o=$container.AddDimAligned((Point3 $e.start),(Point3 $e.end),(Point3 $e.position))
            if ($e.text_height) { $o.TextHeight=[double]$e.text_height; $o.ArrowheadSize=[double]$e.text_height*0.7 }
        }
        'block' {
            $scale=1.0; if ($e.scale) { $scale=[double]$e.scale }
            $o=$container.InsertBlock((Point3 $e.position),[string]$e.name,$scale,$scale,$scale,0.0)
        }
        'filled_circle' {
            # Donut with zero hole: closed two-arc polyline on radius r/2 with constant width r.
            $c=Point3 $e.center; $r=[double]$e.radius
            $o=$container.AddLightWeightPolyline([double[]]@(($c[0]-$r/2),$c[1],($c[0]+$r/2),$c[1]))
            $o.SetBulge(0,1.0); $o.SetBulge(1,1.0); $o.Closed=$true; $o.ConstantWidth=$r; $o.Elevation=0.0
        }
        'filled_polygon' {
            # 2D SOLID corner order is 1-2-4-3; callers give outline order, a triangle repeats its last corner.
            $p=@($e.points | ForEach-Object { ,(Point3 $_) })
            if ($p.Count -eq 3) { $o=$container.AddSolid($p[0],$p[1],$p[2],$p[2]) }
            else { $o=$container.AddSolid($p[0],$p[1],$p[3],$p[2]) }
        }
    }
    # Return immediately; caller tracks the entity before assigning properties.
    return $o
}
# The default Standard style uses txt.shx (Latin-1 only: no ş, ı, ğ, İ, —), so new text gets a TrueType style.
# Created once per drawing; existing styles and objects are left untouched.
$script:unicodeStyleReady=$false
function UnicodeStyle($doc) {
    $name='UNICODE-ARIAL'
    if (-not $script:unicodeStyleReady) {
        try { $s=$doc.TextStyles.Item($name) } catch { $s=$doc.TextStyles.Add($name) }
        # SetFont by typeface; assigning fontFile='arial.ttf' raised "Filer error". Idempotent, so a half-made style is repaired too.
        $s.SetFont('Arial',$false,$false,0,34)
        $script:unicodeStyleReady=$true
    }
    return $name
}
# "Call rejected" (0x80010001) and "retry later" (0x8001010A) mean AutoCAD is momentarily busy.
function IsBusy($err) { return ($err.Exception.ToString() -match '0x80010001|0x8001010A') }
# Only for calls that are safe to repeat (reads, setting a variable to the same value).
function Retry([scriptblock]$call) {
    for ($i=0; $i -lt 20; $i++) {
        try { return (& $call) } catch { if (-not (IsBusy $_) -or $i -eq 19) { throw }; Start-Sleep -Milliseconds 500 }
    }
}
function Info($doc) {
    return @{ drawing=$doc.Name; full_path=$doc.FullName; model_entities=$doc.ModelSpace.Count; units=$doc.GetVariable('INSUNITS'); saved=[bool]$doc.Saved }
}

try {
    $q=[Console]::ReadLine() | ConvertFrom-Json
    $a=$q.arguments
    $app=[Runtime.InteropServices.Marshal]::GetActiveObject('AutoCAD.Application')
    if (-not $app.GetAcadState().IsQuiescent) { throw 'AutoCAD is busy. Finish the active command or close its dialog, then retry.' }
    $doc=$null
    if ($app.Documents.Count -gt 0) { $doc=$app.ActiveDocument }
    if ($q.op -notin @('status','new_drawing')) {
        if ($null -eq $doc) { throw 'Open a drawing first.' }
        if ([string]::IsNullOrWhiteSpace($a.drawing) -or $doc.Name -cne $a.drawing) { throw 'Active drawing changed. Call status and use its exact drawing name.' }
    }
    switch ($q.op) {
        'status' {
            $docs=@(); foreach ($d in $app.Documents) { $docs+=,(Info $d) }
            $styles=@(); if ($doc) { foreach ($s in $doc.TextStyles) { $styles+=@{name=$s.Name;font_file=$s.fontFile} } }
            $result=@{active_drawing=$(if ($doc) {$doc.Name} else {$null}); drawings=$docs; active_text_styles=$styles}
        }
        'new_drawing' {
            # AutoCAD may reject Documents.Add as busy and still open the drawing a moment later.
            # Look for that drawing before trying again, so a rejected call never leaves a second blank drawing.
            # A drawing that is still opening can report an empty name; skip it rather than fail.
            $before=@{}; Retry { foreach ($d in $app.Documents) { $n=$d.Name; if ($n) { $before[$n]=$true } } }
            $doc=$null
            for ($try=0; $try -lt 3 -and $null -eq $doc; $try++) {
                try { $doc=$app.Documents.Add() }
                catch {
                    if (-not (IsBusy $_)) { throw }
                    for ($w=0; $w -lt 20 -and $null -eq $doc; $w++) {
                        Start-Sleep -Milliseconds 500
                        try { foreach ($d in $app.Documents) { $n=$d.Name; if ($n -and -not $before.ContainsKey($n)) { $doc=$d } } } catch {}
                    }
                }
            }
            if ($null -eq $doc) { throw 'AutoCAD did not open a new drawing. Call status before trying again.' }
            Retry { $doc.SetVariable('INSUNITS',[int16]4) }; Retry { $doc.SetVariable('MEASUREMENT',[int16]1) }
            $result=Retry { Info $doc }
        }
        'list_layers' {
            $layers=@(); foreach ($l in $doc.Layers) { $layers+=@{name=$l.Name;color=$l.Color;linetype=$l.Linetype;lineweight=$l.Lineweight;locked=$l.Lock;on=$l.LayerOn} }
            $result=@{drawing=$doc.Name;layers=$layers}
        }
        'create_layer' {
            LayerName $a.name
            $exists=$false; try {$null=$doc.Layers.Item([string]$a.name);$exists=$true} catch {}
            if ($exists) {throw 'Layer already exists; modifying layers is not supported.'}
            $lt='Continuous'
            if ($a.linetype -and $a.linetype -ne 'CONTINUOUS') {
                $lt=[string]$a.linetype
                $loaded=$false; try {$null=$doc.Linetypes.Item($lt);$loaded=$true} catch {}
                if (-not $loaded) { $file='acad.lin'; if ($doc.GetVariable('MEASUREMENT') -eq 1) {$file='acadiso.lin'}; $doc.Linetypes.Load($lt,$file) }
            }
            $doc.StartUndoMark()
            try {
                $l=$doc.Layers.Add([string]$a.name)
                try {
                    $l.Linetype=$lt
                    if ($a.color) {$l.color=[int]$a.color}
                    if ($null -ne $a.lineweight) {$l.Lineweight=[int]$a.lineweight}
                } catch { $msg=$_.Exception.Message; try {$l.Delete()} catch {}; throw $msg }
            } finally {$doc.EndUndoMark()}
            $result=@{drawing=$doc.Name;layer=$l.Name;linetype=$l.Linetype;color=$l.Color;lineweight=$l.Lineweight}
        }
        'list_entities' {
            $limit=100; if ($a.limit) {$limit=[int]$a.limit}; if ($limit -lt 1 -or $limit -gt 500) {throw 'Limit must be 1..500.'}
            $source=$doc.ModelSpace
            if ($a.block) { LayerName $a.block; try {$source=$doc.Blocks.Item([string]$a.block)} catch {throw "Block not found: $($a.block)"} }
            $items=@(); $matched=0
            foreach ($e in $source) {
                if ($a.layer -and $e.Layer -ne $a.layer) {continue}
                $matched++; if ($items.Count -ge $limit) {continue}
                $item=@{handle=$e.Handle;type=$e.ObjectName;layer=$e.Layer}
                if ($e.LinetypeScale -ne 1.0) {$item['LinetypeScale']=$e.LinetypeScale}
                $props=switch ($e.ObjectName) {
                    'AcDbLine' {@('StartPoint','EndPoint')}
                    'AcDbCircle' {@('Center','Radius')}
                    'AcDbPolyline' {@('Coordinates','Closed','ConstantWidth')}
                    {$_ -in @('AcDbSolid','AcDbTrace')} {@('Coordinates')}
                    'AcDbText' {@('TextString','InsertionPoint','StyleName')}
                    'AcDbAlignedDimension' {@('Measurement')}
                    'AcDbBlockReference' {@('Name','InsertionPoint')}
                    default {@()}
                }
                foreach ($prop in $props) {
                    try { $v=$e.$prop; if ($null -ne $v) {$item[$prop]=$v} } catch {}
                }
                # Extents let callers check text overflow and overlaps without seeing the drawing.
                try { $mn=$null; $mx=$null; $e.GetBoundingBox([ref]$mn,[ref]$mx); $item['bbox']=@([math]::Round($mn[0],2),[math]::Round($mn[1],2),[math]::Round($mx[0],2),[math]::Round($mx[1],2)) } catch {}
                $items+=,$item
            }
            $result=@{drawing=$doc.Name;entities=$items;matched=$matched;truncated=($matched -gt $items.Count)}
        }
        {$_ -in @('draw','define_block')} {
            if ($a.entities.Count -lt 1 -or $a.entities.Count -gt 500) {throw 'Provide 1..500 entities.'}
            foreach ($e in $a.entities) {
                CheckEntity $e
                if ($e.type -eq 'block') { $null=$doc.Blocks.Item([string]$e.name) }
                if ($e.layer) {
                    try { $existing=$doc.Layers.Item([string]$e.layer); if ($existing.Lock) {throw 'LOCKED_LAYER'} }
                    catch { if ($_.Exception.Message -match 'LOCKED_LAYER') {throw "Layer is locked: $($e.layer)"} }
                }
            }
            $made=New-Object System.Collections.ArrayList
            $newLayers=New-Object System.Collections.ArrayList
            $block=$null; $undoStarted=$false
            try {
                if ($q.op -eq 'define_block') {
                    LayerName $a.name
                    $exists=$false; try {$null=$doc.Blocks.Item([string]$a.name);$exists=$true} catch {}
                    if ($exists) {throw 'Block already exists; replacement is not supported.'}
                }
                # Prepare the text style before any entity exists, so a style failure leaves nothing behind.
                $textStyle=$null; if (@($a.entities | Where-Object { $_.type -eq 'text' }).Count) { $textStyle=UnicodeStyle $doc }
                $doc.StartUndoMark(); $undoStarted=$true
                $container=$doc.ModelSpace
                if ($q.op -eq 'define_block') { $block=$doc.Blocks.Add([double[]]@(0,0,0),[string]$a.name); $container=$block }
                foreach ($e in $a.entities) {
                    if ($e.layer) {
                        try { $null=$doc.Layers.Item([string]$e.layer) }
                        catch { $l=$doc.Layers.Add([string]$e.layer); $null=$newLayers.Add($l) }
                    }
                    $entity=AddEntity $container $e $doc; $null=$made.Add($entity)
                    if ($e.layer) {$entity.Layer=[string]$e.layer}
                    if ($e.linetype_scale) {$entity.LinetypeScale=[double]$e.linetype_scale}
                    if ($e.type -eq 'text') {$entity.StyleName=$textStyle}
                }
                $handles=@(); foreach ($e in $made) {$handles+=@{handle=$e.Handle;type=$e.ObjectName;layer=$e.Layer}}
                $result=@{drawing=$doc.Name;created=$handles;count=$made.Count;block=$a.name}
            } catch {
                $original=$_.Exception.Message; $rollback=@()
                for ($i=$made.Count-1;$i -ge 0;$i--) {try {$made[$i].Delete()} catch {$rollback+=$_.Exception.Message}}
                if ($block) {try {$block.Delete()} catch {$rollback+=$_.Exception.Message}}
                foreach ($l in $newLayers) {try {$l.Delete()} catch {$rollback+=$_.Exception.Message}}
                throw "$original Rollback errors: $($rollback -join '; ')"
            } finally {if ($undoStarted) {$doc.EndUndoMark()}}
        }
        'zoom_extents' {$doc.Regen(1); $app.ZoomExtents(); $result=@{drawing=$doc.Name;zoomed=$true}}
        'save_as' {
            $path=[IO.Path]::GetFullPath([string]$a.path)
            $root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'drawings'))+[IO.Path]::DirectorySeparatorChar
            if (-not $path.StartsWith($root,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($path) -ne '.dwg') {throw "Save path must be a .dwg inside $root"}
            if (Test-Path -LiteralPath $path) {throw 'File exists; overwriting is not supported. Choose a new filename.'}
            if (-not (Test-Path -LiteralPath ([IO.Path]::GetDirectoryName($path)))) {throw 'Parent directory does not exist.'}
            $doc.SaveAs($path); $result=Info $doc
        }
        default {throw 'Unknown operation.'}
    }
    @{ok=$true;result=$result} | ConvertTo-Json -Depth 30 -Compress | ForEach-Object {[Console]::WriteLine($_)}
} catch {
    @{ok=$false;error=$_.Exception.Message} | ConvertTo-Json -Compress | ForEach-Object {[Console]::WriteLine($_)}
    exit 1
}
