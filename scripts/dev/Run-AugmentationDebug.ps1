try {
  & '.\scripts\Invoke-SttAugmentation.ps1'
} catch {
  $_ | Format-List * -Force
  exit 1
}
