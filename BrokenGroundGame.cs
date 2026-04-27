// BrokenGroundGame.cs  — C# 5 compatible (csc.exe .NET 4.x)
// Self-patching launcher + Spacewar for Broken Ground

using System;
using System.Windows.Forms;
using System.IO;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Drawing;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Reflection;

// ════════════════════════════════════════════════════════════════════════════
static class Program {
    public static string GameDir;
    public static string JoinIP = null;

    [STAThread]
    static void Main(string[] args) {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);

        GameDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);

        for (int i = 0; i < args.Length; i++) {
            string a = args[i].ToLower();
            if ((a == "-join" || a == "+connect" || a == "-connect") && i + 1 < args.Length)
                JoinIP = args[i + 1];
        }

        if (!IsPatched()) {
            Application.Run(new SetupForm());
            if (!IsPatched()) return;
        }

        Application.Run(new LauncherForm());
    }

    public static bool IsPatched() {
        string backup   = Path.Combine(GameDir, "BrokenGround_Data", "Managed", "Assembly-CSharp.dll.backup");
        string settings = Path.Combine(GameDir, "steam_settings");
        return File.Exists(backup) && Directory.Exists(settings);
    }

    public static string GetLocalIP() {
        try {
            using (var s = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, 0)) {
                s.Connect("8.8.8.8", 65530);
                return ((IPEndPoint)s.LocalEndPoint).Address.ToString();
            }
        } catch { return "127.0.0.1"; }
    }
}

// ════════════════════════════════════════════════════════════════════════════
// SETUP FORM
// ════════════════════════════════════════════════════════════════════════════
class SetupForm : Form {
    private ProgressBar progress;
    private RichTextBox  logBox;
    private Label        lblStatus;
    private Button       btnClose;
    private bool         setupDone = false;

    public SetupForm() {
        Text            = "Broken Ground — Kurulum";
        ClientSize      = new Size(560, 390);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        StartPosition   = FormStartPosition.CenterScreen;
        BackColor       = Color.FromArgb(14, 14, 22);
        FormClosing    += (s, e) => { if (!setupDone) e.Cancel = true; };

        var title = new Label {
            Text      = "BROKEN GROUND  —  OTOMATIK KURULUM",
            ForeColor = Color.FromArgb(80, 190, 255),
            Font      = new Font("Segoe UI", 11f, FontStyle.Bold),
            Location  = new Point(0, 14),
            Size      = new Size(560, 26),
            TextAlign = ContentAlignment.MiddleCenter
        };

        lblStatus = new Label {
            Text      = "Hazirlanıyor...",
            ForeColor = Color.LightGray,
            Font      = new Font("Segoe UI", 9f),
            Location  = new Point(14, 46),
            Size      = new Size(530, 20)
        };

        progress = new ProgressBar {
            Location = new Point(14, 70),
            Size     = new Size(530, 18),
            Minimum  = 0,
            Maximum  = 100,
            Style    = ProgressBarStyle.Continuous
        };

        logBox = new RichTextBox {
            Location    = new Point(14, 100),
            Size        = new Size(530, 240),
            BackColor   = Color.FromArgb(8, 8, 14),
            ForeColor   = Color.FromArgb(160, 210, 160),
            Font        = new Font("Consolas", 8.5f),
            ReadOnly    = true,
            ScrollBars  = RichTextBoxScrollBars.Vertical,
            BorderStyle = BorderStyle.FixedSingle
        };

        btnClose = new Button {
            Text      = "Kapat",
            Location  = new Point(440, 350),
            Size      = new Size(104, 30),
            BackColor = Color.FromArgb(60, 30, 30),
            ForeColor = Color.White,
            FlatStyle = FlatStyle.Flat,
            Enabled   = false
        };
        btnClose.Click += (s, e) => Close();

        Controls.AddRange(new Control[] { title, lblStatus, progress, logBox, btnClose });
        Load += (s, e) => new Thread(RunSetup) { IsBackground = true }.Start();
    }

    void WriteLog(string line, Color? color = null) {
        if (InvokeRequired) { Invoke(new Action<string, Color?>(WriteLog), line, color); return; }
        logBox.SelectionColor = color ?? Color.FromArgb(160, 210, 160);
        logBox.AppendText(line + "\n");
        logBox.ScrollToCaret();
    }

    void SetStatus(string text, int pct) {
        if (InvokeRequired) { Invoke(new Action<string, int>(SetStatus), text, pct); return; }
        lblStatus.Text = text;
        progress.Value = Math.Min(pct, 100);
    }

    void Finish(bool ok) {
        if (InvokeRequired) { Invoke(new Action<bool>(Finish), ok); return; }
        setupDone = true;
        btnClose.Enabled   = true;
        btnClose.BackColor = ok ? Color.FromArgb(25, 80, 25) : Color.FromArgb(80, 25, 25);
        btnClose.Text      = ok ? "Tamamlandi  →  Baslat" : "Kapat (Hata)";
    }

    void RunSetup() {
        try {
            SetStatus("patch.ps1 aranıyor / indiriliyor...", 5);
            string ps1 = FindOrDownloadPs1();
            WriteLog("Patch: " + ps1, Color.Cyan);

            SetStatus("Yamalar uygulanıyor...", 15);
            RunPs1(ps1);

            SetStatus("Spacewar AppID ayarlanıyor...", 90);
            SetSpacewarId();

            SetStatus("Kurulum tamamlandi!", 100);
            WriteLog("", null);
            WriteLog("Tum yamalar basariyla uygulandı.", Color.LimeGreen);
            WriteLog("Spacewar AppID 480 ayarlandı.", Color.LimeGreen);
            WriteLog("", null);
            WriteLog("STEAM'E EKLEMEK ICIN:", Color.Yellow);
            WriteLog("  Steam → Library sol ust '+' → Add a Non-Steam Game", Color.Yellow);
            WriteLog("  BrokenGroundGame.exe'yi sec", Color.Yellow);
            WriteLog("  Oyun adini 'Spacewar' olarak degistir", Color.Yellow);
            WriteLog("  Arkadaslarin seni 'Spacewar oynuyor' gorecek!", Color.Yellow);
            Finish(true);
        } catch (Exception ex) {
            WriteLog("HATA: " + ex.Message, Color.Red);
            WriteLog("patch.ps1'i elle calistirmayi deneyin.", Color.Yellow);
            Finish(false);
        }
    }

    string FindOrDownloadPs1() {
        string local = Path.Combine(Program.GameDir, "patch.ps1");
        if (File.Exists(local)) { WriteLog("  Bulundu: " + local); return local; }

        // TLS 1.2 gerekli (GitHub, .NET 4.x default TLS1.0 kullanir)
        ServicePointManager.SecurityProtocol =
            SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;

        WriteLog("  GitHub'dan indiriliyor...", Color.Yellow);
        string tmp = Path.Combine(Path.GetTempPath(), "bg_patch_dl.ps1");
        using (var wc = new WebClient()) {
            wc.Headers["User-Agent"] = "BrokenGroundGame/2.0";
            wc.DownloadFile(
                "https://raw.githubusercontent.com/Evilpata/Broken-Ground/main/patch.ps1",
                tmp);
        }
        WriteLog("  Indirildi.");
        return tmp;
    }

    void RunPs1(string ps1Path) {
        var psi = new ProcessStartInfo {
            FileName               = "powershell.exe",
            Arguments              = "-NonInteractive -ExecutionPolicy Bypass -File \"" + ps1Path + "\"",
            UseShellExecute        = false,
            RedirectStandardOutput = true,
            RedirectStandardError  = true,
            CreateNoWindow         = true,
            WorkingDirectory       = Program.GameDir
        };

        using (var proc = Process.Start(psi)) {
            proc.OutputDataReceived += (s, e) => {
                if (e.Data == null) return;
                string line = e.Data.TrimEnd();
                if (line.Contains("HATA") || line.Contains("Error"))
                    WriteLog(line, Color.Red);
                else if (line.StartsWith("  ["))
                    WriteLog(line, Color.FromArgb(100, 220, 100));
                else if (line.Contains("indiriliyor") || line.Contains("yukleniyor"))
                    WriteLog(line, Color.Yellow);
                else
                    WriteLog(line);
            };
            proc.ErrorDataReceived += (s, e) => {
                if (e.Data != null) WriteLog("[PS] " + e.Data, Color.FromArgb(255, 160, 80));
            };
            proc.BeginOutputReadLine();
            proc.BeginErrorReadLine();
            proc.WaitForExit();
            if (proc.ExitCode != 0)
                throw new Exception("PowerShell cikis kodu: " + proc.ExitCode);
        }
    }

    void SetSpacewarId() {
        string appIdPath = Path.Combine(Program.GameDir, "steam_appid.txt");
        File.WriteAllText(appIdPath, "480", Encoding.ASCII);
        WriteLog("  steam_appid.txt = 480 (Spacewar)");

        string cfgMain = Path.Combine(Program.GameDir, "steam_settings", "configs.main.ini");
        if (File.Exists(cfgMain)) {
            string c = File.ReadAllText(cfgMain);
            c = Regex.Replace(c, @"appid=\d+", "appid=480");
            File.WriteAllText(cfgMain, c);
            WriteLog("  Goldberg configs → appid=480");
        }
    }
}

// ════════════════════════════════════════════════════════════════════════════
// LAUNCHER FORM
// ════════════════════════════════════════════════════════════════════════════
class LauncherForm : Form {
    private TextBox tbName;
    private Button  btnPlay;
    private Label   lblIPValue;
    private Button  btnCopyIP;
    private Panel   panelJoin;
    private TextBox tbJoinIP;
    private string  hostIP;
    private bool    joinPanelOpen = false;
    private Button  btnToggleJoin;

    public LauncherForm() {
        hostIP = Program.GetLocalIP();

        Text            = "Broken Ground";
        ClientSize      = new Size(400, 295);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox     = false;
        StartPosition   = FormStartPosition.CenterScreen;
        BackColor       = Color.FromArgb(14, 14, 22);
        TrySetIcon();

        BuildUI();
    }

    void BuildUI() {
        // ── Header ─────────────────────────────────────────────────────────
        var strip = new Panel {
            Location  = new Point(0, 0),
            Size      = new Size(400, 48),
            BackColor = Color.FromArgb(8, 8, 16)
        };
        strip.Controls.Add(new Label {
            Text      = "BROKEN GROUND",
            ForeColor = Color.FromArgb(80, 190, 255),
            Font      = new Font("Segoe UI", 14f, FontStyle.Bold),
            Location  = new Point(0, 8),
            Size      = new Size(400, 26),
            TextAlign = ContentAlignment.MiddleCenter
        });
        strip.Controls.Add(new Label {
            Text      = "Local Multiplayer  —  Spacewar (480)",
            ForeColor = Color.FromArgb(80, 80, 120),
            Font      = new Font("Segoe UI", 8f),
            Location  = new Point(0, 33),
            Size      = new Size(400, 14),
            TextAlign = ContentAlignment.MiddleCenter
        });

        // ── Name ───────────────────────────────────────────────────────────
        Controls.Add(MkLabel("Karakter Ismi:", new Point(20, 60)));
        tbName = new TextBox {
            Location    = new Point(20, 78),
            Size        = new Size(360, 26),
            BackColor   = Color.FromArgb(28, 28, 44),
            ForeColor   = Color.White,
            BorderStyle = BorderStyle.FixedSingle,
            Font        = new Font("Segoe UI", 11f),
            Text        = LoadSavedName()
        };

        // ── Mode label ─────────────────────────────────────────────────────
        string modeText = Program.JoinIP != null
            ? "Mod: JOIN (Steam daveti)  →  " + Program.JoinIP
            : "Mod: HOST  —  arkadaşlarını davet et";
        var lblMode = new Label {
            Text      = modeText,
            ForeColor = Program.JoinIP != null ? Color.FromArgb(255, 190, 80) : Color.FromArgb(90, 200, 90),
            Font      = new Font("Segoe UI", 8f),
            Location  = new Point(20, 108),
            Size      = new Size(360, 16)
        };

        // ── PLAY button ────────────────────────────────────────────────────
        string playText = Program.JoinIP != null ? "  JOIN GAME" : "  OYNA  (HOST)";
        Color  playColor = Program.JoinIP != null
            ? Color.FromArgb(90, 50, 15)
            : Color.FromArgb(18, 75, 140);
        btnPlay = MkButton(playText, new Point(20, 130), new Size(360, 46), playColor);
        btnPlay.Font   = new Font("Segoe UI", 13f, FontStyle.Bold);
        btnPlay.Click += OnPlay;

        // ── Divider ────────────────────────────────────────────────────────
        var div = new Panel {
            Location  = new Point(20, 188),
            Size      = new Size(360, 1),
            BackColor = Color.FromArgb(45, 45, 65)
        };

        // ── IP section ─────────────────────────────────────────────────────
        Controls.Add(MkLabel("Senin IP Adresin  (arkadaşa gonder):", new Point(20, 196)));
        lblIPValue = new Label {
            Text      = hostIP,
            ForeColor = Color.FromArgb(255, 220, 70),
            Font      = new Font("Consolas", 13f, FontStyle.Bold),
            Location  = new Point(20, 213),
            Size      = new Size(280, 26)
        };
        btnCopyIP = MkButton("Kopyala", new Point(308, 213), new Size(72, 26),
                             Color.FromArgb(35, 55, 95));
        btnCopyIP.Font   = new Font("Segoe UI", 8f);
        btnCopyIP.Click += OnCopyIP;

        // ── Toggle join panel ──────────────────────────────────────────────
        btnToggleJoin = MkButton("Arkadas IP ile Katil  v", new Point(20, 250),
                                 new Size(360, 26), Color.FromArgb(50, 28, 28));
        btnToggleJoin.Font   = new Font("Segoe UI", 8.5f);
        btnToggleJoin.Click += OnToggleJoin;

        // ── Join panel (hidden) ────────────────────────────────────────────
        panelJoin = new Panel {
            Location  = new Point(20, 282),
            Size      = new Size(360, 32),
            Visible   = false
        };
        tbJoinIP = new TextBox {
            Location    = new Point(0, 4),
            Size        = new Size(256, 24),
            BackColor   = Color.FromArgb(28, 28, 44),
            ForeColor   = Color.White,
            BorderStyle = BorderStyle.FixedSingle,
            Font        = new Font("Segoe UI", 10f),
            Text        = ""
        };
        var btnJoin = MkButton("KATIL", new Point(262, 4), new Size(98, 24),
                               Color.FromArgb(90, 48, 12));
        btnJoin.Click += OnJoin;
        panelJoin.Controls.AddRange(new Control[] { tbJoinIP, btnJoin });

        // ── IP section hidden in JOIN mode ─────────────────────────────────
        bool showIP = (Program.JoinIP == null);
        div.Visible          = showIP;
        lblIPValue.Visible   = showIP;
        btnCopyIP.Visible    = showIP;
        btnToggleJoin.Visible = showIP;
        var lblIPTitle = MkLabel("Senin IP Adresin  (arkadasa gonder):", new Point(20, 196));
        lblIPTitle.Visible = showIP;
        Controls.Add(lblIPTitle);

        Controls.AddRange(new Control[] {
            strip, tbName, lblMode, btnPlay,
            div, lblIPValue, btnCopyIP,
            btnToggleJoin, panelJoin
        });

        if (!showIP) ClientSize = new Size(400, 192);
    }

    Label MkLabel(string text, Point loc) {
        return new Label {
            Text      = text,
            ForeColor = Color.FromArgb(130, 130, 165),
            Font      = new Font("Segoe UI", 8f),
            Location  = loc,
            Size      = new Size(360, 16)
        };
    }

    // Helper overload that also returns the label (for .Visible assignment)
    Label AddLabel(string text, Point loc) {
        var l = MkLabel(text, loc);
        Controls.Add(l);
        return l;
    }

    Button MkButton(string text, Point loc, Size sz, Color bg) {
        var b = new Button {
            Text      = text,
            Location  = loc,
            Size      = sz,
            BackColor = bg,
            ForeColor = Color.White,
            FlatStyle = FlatStyle.Flat,
            Cursor    = Cursors.Hand
        };
        b.FlatAppearance.BorderColor = Color.FromArgb(65, 65, 90);
        return b;
    }

    void OnPlay(object sender, EventArgs e) {
        string name = ValidateName();
        if (Program.JoinIP != null)
            DoLaunch("join", Program.JoinIP, name);
        else
            DoLaunch("host", "", name);
    }

    void OnJoin(object sender, EventArgs e) {
        string ip = tbJoinIP.Text.Trim();
        if (string.IsNullOrEmpty(ip)) { MessageBox.Show("IP adresi girin.", "Hata"); return; }
        DoLaunch("join", ip, ValidateName());
    }

    void OnCopyIP(object sender, EventArgs e) {
        Clipboard.SetText(hostIP);
        btnCopyIP.Text = "Kopyalandı!";
        var t = new System.Windows.Forms.Timer { Interval = 1600 };
        t.Tick += (ts, te) => { btnCopyIP.Text = "Kopyala"; t.Stop(); };
        t.Start();
    }

    void OnToggleJoin(object sender, EventArgs e) {
        joinPanelOpen = !joinPanelOpen;
        panelJoin.Visible     = joinPanelOpen;
        btnToggleJoin.Text    = joinPanelOpen
            ? "Arkadas IP ile Katil  ^"
            : "Arkadas IP ile Katil  v";
        ClientSize = new Size(400, joinPanelOpen ? 326 : 295);
    }

    string ValidateName() {
        string name = tbName.Text.Trim();
        if (string.IsNullOrEmpty(name)) { name = "Player1"; tbName.Text = name; }
        if (name.Length > 32) name = name.Substring(0, 32);
        SaveName(name);
        return name;
    }

    void DoLaunch(string mode, string ip, string name) {
        WriteGoldbergSettings(name, mode, ip);

        try {
            File.WriteAllText(
                Path.Combine(Program.GameDir, "launcher_config.ini"),
                "name=" + name + "\nmode=" + mode + "\nip=" + ip + "\n");
        } catch { }

        var psi = new ProcessStartInfo {
            FileName         = Path.Combine(Program.GameDir, "BrokenGround.exe"),
            WorkingDirectory = Program.GameDir,
            UseShellExecute  = false
        };
        psi.EnvironmentVariables["BG_NAME"] = name;
        psi.EnvironmentVariables["BG_MODE"] = mode;
        psi.EnvironmentVariables["BG_IP"]   = ip;

        try { Process.Start(psi); Application.Exit(); }
        catch (Exception ex) {
            MessageBox.Show("Oyun baslatılamadı:\n" + ex.Message, "Hata",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    void WriteGoldbergSettings(string name, string mode, string ip) {
        try {
            string dir = Path.Combine(Program.GameDir, "steam_settings");
            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, "account_name.txt"), name);
            long steamId = 76561198000000000L + (Math.Abs(name.GetHashCode()) % 999998L + 1L);
            File.WriteAllText(Path.Combine(dir, "user_steam_id.txt"), steamId.ToString());
            File.WriteAllText(Path.Combine(dir, "configs.user.ini"),
                "[user::general]\r\naccount_name=" + name + "\r\n");
            // Rich presence for friends to see host IP
            string rp = mode == "host"
                ? "[Status]\nstatus=Hosting (" + hostIP + ")\nconnect=+join " + hostIP + "\n"
                : "[Status]\nstatus=Playing\n";
            File.WriteAllText(Path.Combine(dir, "richpresence.ini"), rp);
        } catch { }
    }

    string LoadSavedName() {
        try {
            string cfg = Path.Combine(Program.GameDir, "launcher_config.ini");
            if (!File.Exists(cfg)) return "Player1";
            foreach (string line in File.ReadAllLines(cfg))
                if (line.StartsWith("name=")) return line.Substring(5).Trim();
        } catch { }
        return "Player1";
    }

    void SaveName(string name) {
        try {
            string cfg  = Path.Combine(Program.GameDir, "launcher_config.ini");
            string text = File.Exists(cfg) ? File.ReadAllText(cfg) : "";
            text = Regex.IsMatch(text, @"name=")
                ? Regex.Replace(text, @"name=[^\n]*", "name=" + name)
                : "name=" + name + "\n" + text;
            File.WriteAllText(cfg, text);
        } catch { }
    }

    void TrySetIcon() {
        try { Icon = Icon.ExtractAssociatedIcon(Path.Combine(Program.GameDir, "BrokenGround.exe")); }
        catch { }
    }
}
