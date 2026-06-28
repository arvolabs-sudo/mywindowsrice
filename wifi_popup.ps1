# WPF WiFi Popup for YASB — Catppuccin Mocha Theme
# Fully rewritten: modern UI, async scanning, password support

$mutex = New-Object System.Threading.Mutex($false, "YASB_WiFi_Popup_Mutex")
if (!$mutex.WaitOne(0, $false)) { exit }

try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

    # ── XAML UI Definition ──────────────────────────────────────
    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WiFi" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" SizeToContent="WidthAndHeight"
        ResizeMode="NoResize" SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Display"
        UseLayoutRounding="True">
    <Window.Resources>
        <Style x:Key="HoverBorder" TargetType="Border">
            <Setter Property="Background" Value="Transparent"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#313244"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="AccentButton" TargetType="Button">
            <Setter Property="Background" Value="#cba6f7"/>
            <Setter Property="Foreground" Value="#1e1e2e"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Padding" Value="12,5"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#b4befe"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="IconButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bd" Background="{TemplateBinding Background}" CornerRadius="6" Padding="4,2">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="#313244"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Border Background="#E61e1e2e" CornerRadius="12" BorderThickness="1" BorderBrush="#585b70" Margin="8">
        <Border.Effect>
            <DropShadowEffect BlurRadius="20" ShadowDepth="2" Opacity="0.5" Color="Black"/>
        </Border.Effect>
        <StackPanel Width="280" MinHeight="100">
            <!-- Header -->
            <Grid Margin="14,12,14,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" Text="WiFi Networks" Foreground="#cba6f7" FontFamily="Segoe UI" FontSize="14" FontWeight="Bold" VerticalAlignment="Center"/>
                <Button Grid.Column="1" x:Name="RefreshBtn" Style="{StaticResource IconButton}" ToolTip="Refresh">
                    <TextBlock Text="&#xe72c;" FontFamily="Segoe MDL2 Assets" Foreground="#bac2de" FontSize="13"/>
                </Button>
            </Grid>
            <Border Height="1" Background="#45475a" Margin="14,8,14,4"/>

            <!-- Status -->
            <TextBlock x:Name="StatusLabel" Text="Initializing..." Foreground="#a6adc8" FontFamily="Segoe UI" FontSize="11" Margin="14,4,14,2"/>

            <!-- Network list -->
            <ScrollViewer MaxHeight="340" VerticalScrollBarVisibility="Auto" Margin="6,2,6,4">
                <StackPanel x:Name="NetworkPanel"/>
            </ScrollViewer>

            <!-- Password prompt (hidden) -->
            <StackPanel x:Name="PasswordPanel" Visibility="Collapsed" Margin="14,4,14,10">
                <TextBlock x:Name="PasswordTitle" Text="Enter password:" Foreground="#bac2de" FontFamily="Segoe UI" FontSize="11" Margin="0,0,0,5"/>
                <Grid>
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>
                    <Border Grid.Column="0" Background="#313244" CornerRadius="6" BorderThickness="1" BorderBrush="#45475a" Padding="2">
                        <PasswordBox x:Name="PasswordInput" Background="Transparent" Foreground="#cdd6f4" BorderThickness="0" FontFamily="Segoe UI" FontSize="12" Padding="4,3" VerticalContentAlignment="Center" CaretBrush="#cdd6f4"/>
                    </Border>
                    <Button Grid.Column="1" x:Name="ConnectBtn" Content="Connect" Margin="6,0,0,0" Style="{StaticResource AccentButton}"/>
                </Grid>
            </StackPanel>

            <!-- Bottom padding when no password panel -->
            <Border x:Name="BottomSpacer" Height="8"/>
        </StackPanel>
    </Border>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [System.Windows.Markup.XamlReader]::Load($reader)

    # ── Element References ──────────────────────────────────────
    $refreshBtn    = $window.FindName("RefreshBtn")
    $statusLabel   = $window.FindName("StatusLabel")
    $networkPanel  = $window.FindName("NetworkPanel")
    $passwordPanel = $window.FindName("PasswordPanel")
    $passwordTitle = $window.FindName("PasswordTitle")
    $passwordInput = $window.FindName("PasswordInput")
    $connectBtn    = $window.FindName("ConnectBtn")
    $bottomSpacer  = $window.FindName("BottomSpacer")

    # ── State ───────────────────────────────────────────────────
    $script:selectedSSID = ""
    $script:scanning     = $false
    $script:asyncPS      = $null
    $script:asyncRS      = $null
    $script:asyncHandle  = $null

    # ── Build a single network row (Border) ────────────────────
    function New-NetworkRow($ssid, $signal, $isConnected) {
        $iconChar = [char]0xE871
        if     ($signal -gt 80) { $iconChar = [char]0xE701 }
        elseif ($signal -gt 60) { $iconChar = [char]0xE874 }
        elseif ($signal -gt 40) { $iconChar = [char]0xE873 }
        elseif ($signal -gt 20) { $iconChar = [char]0xE872 }

        $border = New-Object System.Windows.Controls.Border
        $border.CornerRadius = 8; $border.Padding = "10,7,10,7"; $border.Margin = "2,1,2,1"; $border.Cursor = "Hand"
        $border.Background = "Transparent"; $border.Tag = $ssid
        $border.Add_MouseEnter({ $this.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#313244") })
        $border.Add_MouseLeave({ $this.Background = "Transparent" })

        $grid = New-Object System.Windows.Controls.Grid
        $col0 = New-Object System.Windows.Controls.ColumnDefinition; $col0.Width = "Auto"
        $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = "*"
        $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = "Auto"
        $grid.ColumnDefinitions.Add($col0); $grid.ColumnDefinitions.Add($col1); $grid.ColumnDefinitions.Add($col2)

        if ($isConnected) {
            $dot = New-Object System.Windows.Shapes.Ellipse; $dot.Width = 7; $dot.Height = 7
            $dot.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#a6e3a1")
            $dot.Margin = "0,0,8,0"; $dot.VerticalAlignment = "Center"
            [System.Windows.Controls.Grid]::SetColumn($dot, 0); $grid.Children.Add($dot) | Out-Null
        }

        $tb = New-Object System.Windows.Controls.TextBlock; $tb.Text = $ssid; $tb.FontFamily = "Segoe UI"; $tb.FontSize = 13; $tb.VerticalAlignment = "Center"
        $tb.TextTrimming = "CharacterEllipsis"; $tb.MaxWidth = 190
        $tbColor = if ($isConnected) { "#cba6f7" } else { "#cdd6f4" }
        $tb.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($tbColor)
        if ($isConnected) { $tb.FontWeight = "SemiBold" }
        [System.Windows.Controls.Grid]::SetColumn($tb, 1); $grid.Children.Add($tb) | Out-Null

        $si = New-Object System.Windows.Controls.TextBlock; $si.Text = [string]$iconChar; $si.FontFamily = "Segoe MDL2 Assets"; $si.FontSize = 14; $si.VerticalAlignment = "Center"
        $si.Margin = "6,0,0,0"
        $siColor = if ($isConnected) { "#a6e3a1" } else { "#6c7086" }
        $si.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($siColor)
        [System.Windows.Controls.Grid]::SetColumn($si, 2); $grid.Children.Add($si) | Out-Null

        $border.Child = $grid
        $border.Add_MouseLeftButtonUp({ param($sender, $e) Handle-NetworkClick $sender.Tag })
        return $border
    }

    function Handle-NetworkClick($ssid) {
        $iface = netsh wlan show interfaces 2>$null
        $current = ""
        foreach ($l in $iface) { if ($l -match "^\s*SSID\s*:\s*(.*)$") { $current = $matches[1].Trim(); break } }
        
        if ($ssid -eq $current) {
            $statusLabel.Text = "Disconnecting..."
            netsh wlan disconnect 2>$null | Out-Null
            Start-BackgroundScan
            return
        }
        if ((netsh wlan show profiles 2>$null) -match ":\s*$([regex]::Escape($ssid))\s*$") {
            $statusLabel.Text = "Connecting to $ssid..."
            netsh wlan connect name="$ssid" 2>$null | Out-Null
            $delayTimer = New-Object System.Windows.Threading.DispatcherTimer
            $delayTimer.Interval = [TimeSpan]::FromSeconds(3)
            $delayTimer.Add_Tick({ $this.Stop(); Start-BackgroundScan })
            $delayTimer.Start()
        } else {
            $script:selectedSSID = $ssid; $passwordTitle.Text = "Password for '$ssid':"
            $passwordPanel.Visibility = "Visible"; $bottomSpacer.Height = 0
            $passwordInput.Clear(); $passwordInput.Focus()
        }
    }

    function Connect-WithPassword($ssid, $password) {
        $statusLabel.Text = "Connecting to $ssid..."
        $hex = -join ($ssid.ToCharArray() | ForEach-Object { '{0:X2}' -f [int]$_ })
        $profileXml = "<?xml version=`"1.0`"?><WLANProfile xmlns=`"http://www.microsoft.com/networking/WLAN/profile/v1`"><name>$([System.Security.SecurityElement]::Escape($ssid))</name><SSIDConfig><SSID><hex>$hex</hex><name>$([System.Security.SecurityElement]::Escape($ssid))</name></SSID></SSIDConfig><connectionType>ESS</connectionType><connectionMode>auto</connectionMode><MSM><security><authEncryption><authentication>WPA2PSK</authentication><encryption>AES</encryption><useOneX>false</useOneX></authEncryption><sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>$([System.Security.SecurityElement]::Escape($password))</keyMaterial></sharedKey></security></MSM></WLANProfile>"
        $xmlPath = Join-Path $env:TEMP "yasb_wifi_profile.xml"; [System.IO.File]::WriteAllText($xmlPath, $profileXml, [System.Text.Encoding]::UTF8)
        netsh wlan add profile filename="$xmlPath" 2>$null | Out-Null; Remove-Item $xmlPath -Force -ErrorAction SilentlyContinue
        netsh wlan connect name="$ssid" 2>$null | Out-Null
        $passwordPanel.Visibility = "Collapsed"; $bottomSpacer.Height = 8
        $delayTimer = New-Object System.Windows.Threading.DispatcherTimer
        $delayTimer.Interval = [TimeSpan]::FromSeconds(3)
        $delayTimer.Add_Tick({ $this.Stop(); Start-BackgroundScan })
        $delayTimer.Start()
    }

    function Start-BackgroundScan {
        if ($script:scanning) { return }
        $script:scanning = $true
        $statusLabel.Text = "Scanning nearby networks..."
        if ($script:asyncPS) { try { $script:asyncPS.Dispose() } catch {}; try { $script:asyncRS.Close() } catch {} }
        
        $script:asyncRS = [runspacefactory]::CreateRunspace()
        $script:asyncRS.Open()
        $script:asyncPS = [powershell]::Create()
        $script:asyncPS.Runspace = $script:asyncRS
        $script:asyncPS.AddScript({
            $networks = @()
            try {
                $iface = netsh wlan show interfaces 2>$null
                $currentSSID = ""
                foreach ($l in $iface) { if ($l -match "^\s*SSID\s*:\s*(.*)$") { $currentSSID = $matches[1].Trim(); break } }
                
                $raw = netsh wlan show networks mode=bssid 2>$null
                $tempSSID = ""
                foreach ($line in ($raw -split "`r?`n")) {
                    if ($line -match "SSID \d+ : (.+)") {
                        $tempSSID = $matches[1].Trim()
                    }
                    elseif ($line -match "Signal\s*:\s*(\d+)%") {
                        if ($tempSSID) {
                            $networks += [PSCustomObject]@{ SSID=$tempSSID; Signal=[int]$matches[1]; IsConnected=($tempSSID -eq $currentSSID) }
                            $tempSSID = ""
                        }
                    }
                }
            } catch {}
            return @($networks | Group-Object SSID | ForEach-Object { $_.Group | Sort-Object Signal -Descending | Select-Object -First 1 } | Sort-Object @{Expression={$_.IsConnected}; Descending=$true}, @{Expression={$_.Signal}; Descending=$true})
        }) | Out-Null

        $script:asyncHandle = $script:asyncPS.BeginInvoke()
        $pollTimer = New-Object System.Windows.Threading.DispatcherTimer
        $pollTimer.Interval = [TimeSpan]::FromMilliseconds(150)
        $pollTimer.Add_Tick({
            if ($script:asyncHandle.IsCompleted) {
                $this.Stop()
                try {
                    $results = @($script:asyncPS.EndInvoke($script:asyncHandle))
                    $networkPanel.Children.Clear()
                    if ($results.Count -eq 0) {
                        $noNet = New-Object System.Windows.Controls.TextBlock; $noNet.Text = "No networks found"; $noNet.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#6c7086")
                        $noNet.FontFamily = "Segoe UI"; $noNet.FontSize = 12; $noNet.Margin = "10,8,10,8"; $noNet.HorizontalAlignment = "Center"
                        $networkPanel.Children.Add($noNet) | Out-Null
                    } else {
                        foreach ($net in $results) { $networkPanel.Children.Add((New-NetworkRow $net.SSID $net.Signal $net.IsConnected)) | Out-Null }
                    }
                    $statusLabel.Text = "$($results.Count) network(s) found"
                } catch { $statusLabel.Text = "Scan error" }
                $script:scanning = $false
            }
        })
        $pollTimer.Start()
    }

    $refreshBtn.Add_Click({ Start-BackgroundScan })
    $connectBtn.Add_Click({ if ($passwordInput.Password -and $script:selectedSSID) { Connect-WithPassword $script:selectedSSID $passwordInput.Password; $passwordInput.Clear() } })
    $passwordInput.Add_KeyDown({ if ($_.Key -eq "Return" -and $passwordInput.Password -and $script:selectedSSID) { Connect-WithPassword $script:selectedSSID $passwordInput.Password; $passwordInput.Clear() } })
    $window.Add_Deactivated({ $window.Close() })

    # ── Positioning ─────────────────────────────────────────────
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $dpiX = 1.0; try { $graphics = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $dpiX = $graphics.DpiX / 96; $graphics.Dispose() } catch {}
    $window.Left = ($screen.Right / $dpiX) - 305
    $window.Top  = ($screen.Top / $dpiX) - 5

    $autoRefresh = New-Object System.Windows.Threading.DispatcherTimer
    $autoRefresh.Interval = [TimeSpan]::FromSeconds(12)
    $autoRefresh.Add_Tick({ Start-BackgroundScan })
    $autoRefresh.Start()
    
    $window.Add_ContentRendered({ Start-BackgroundScan })
    $window.ShowDialog() | Out-Null
    
    $autoRefresh.Stop()
    if ($script:asyncPS) { try { $script:asyncPS.Dispose() } catch {}; try { $script:asyncRS.Close() } catch {} }

} catch {
    [System.Windows.MessageBox]::Show("Error: $($_.Exception.Message)", "WiFi Popup Error")
} finally {
    if ($mutex) { $mutex.ReleaseMutex() }
}