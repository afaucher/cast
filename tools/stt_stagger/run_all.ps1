# run_all.ps1 - the full measurement set behind docs/design/stt-latency-staggered-streams.md
# (about two hours of real-time audio; run with the machine otherwise idle).
$b = Join-Path $PSScriptRoot "run_bench.ps1"
if ($args -notcontains "-SkipStagger") {
    & $b -Streams 0 -Tag probe-n0
    & $b -Streams 1 -Phases 12 -Groups "clean,rate" -Tag n1-sweep
    & $b -Streams 2 -Phases 6 -Groups "clean,rate" -Tag n2
    & $b -Streams 3 -Phases 4 -Groups "clean,rate" -Tag n3
}
& $b -Streams 1 -Phases 4 -Groups "clean,rate" -Flush 1000 -Quiet 100 -SoftDb 15 -Tag flush1000-q100-s15
& $b -Streams 1 -Phases 4 -Groups "clean,rate" -Flush 1000 -Quiet 100 -SoftDb 6 -Tag flush1000-q100-s6
& $b -Streams 1 -Phases 4 -Groups "hesitate,sloppy" -Tag hs-base
& $b -Streams 1 -Phases 4 -Groups "hesitate,sloppy" -Flush 1000 -Quiet 100 -SoftDb 15 -Tag hs-flush1000-q100-s15
& $b -Streams 1 -Phases 4 -Groups "hesitate,sloppy" -Flush 1000 -Quiet 100 -SoftDb 6 -Tag hs-flush1000-q100-s6
& $b -Streams 1 -Phases 4 -Groups "hesitate,sloppy" -Flush 1000 -Quiet 60 -SoftDb 15 -Tag hs-flush1000-q60-s15
& $b -Streams 1 -Phases 4 -Groups "hesitate,sloppy" -Flush 1400 -Quiet 100 -SoftDb 15 -Tag hs-flush1400-q100-s15
& $b -Streams 2 -Phases 2 -Groups "hesitate,sloppy" -Tag hs-n2
Write-Host "ALL DONE"
