# Broken Ground — Local Multiplayer Patch

> Sunucuları kapanan **Broken Ground** oyununu arkadaşlarınla **LAN veya ZeroTier** üzerinden oynamanı sağlayan yama.  
> Steam login, PlayFab ve online sunucuya ihtiyaç yok.

---

## 📦 İçerik

| Dosya | Açıklama |
|-------|----------|
| `patch.ps1` | Oyunu yamalar (1 tıkla çalışır) |
| `BrokenGroundLauncher.exe` | Oyun başlatıcı (isim + mod seçimi) |

---

## ⚡ Kurulum (2 adım)

### 1. Patch uygula
1. Bu repoyu ZIP olarak indir → **Code → Download ZIP**
2. ZIP'i aç, klasörü bir yere koy
3. `patch.ps1` dosyasına **sağ tıkla → "PowerShell ile Çalıştır"**
4. Oyun klasörünü otomatik bulur ve yamar

> **Not:** Windows "güvenlik uyarısı" çıkarsa → "Yine de çalıştır" de.  
> Script zararlı değil, sadece oyunun DLL dosyasını düzenler.

### 2. Oyunu başlat
- `BrokenGroundLauncher.exe` **otomatik olarak** oyun klasörüne kopyalanır
- Artık oyunu her zaman `BrokenGroundLauncher.exe` ile aç (Steam'den değil)

---

## 🎮 Nasıl Oynanır

### Tek Kişi (Practice)
1. `BrokenGroundLauncher.exe` aç
2. Karakter ismi yaz
3. **SINGLE PLAYER** tıkla

### Host Ol (Arkadaşları davet et)
1. `BrokenGroundLauncher.exe` aç
2. Karakter ismi yaz → **HOST GAME** tıkla
3. Oyun açılır → **Multiplayer → Quick Play**
4. Lokal sunucu otomatik başlar
5. IP adresini arkadaşlara ver (aşağıya bak)

### Arkadaşa Katıl
1. `BrokenGroundLauncher.exe` aç
2. Karakter ismi yaz → **JOIN GAME** tıkla
3. Host'un IP adresini gir → **CONNECT**
4. Oyun açılır → **Multiplayer → Quick Play**

---

## 🌐 ZeroTier ile İnternetten Oynama

> Router ayarı gerektirmez! ZeroTier ücretsiz ve kolaydır.

1. [zerotier.com](https://www.zerotier.com/download/) → ZeroTier One'ı indir ve kur
2. **Host:** ZeroTier arayüzünde → "Create Network" → **Network ID**'yi kopyala
3. **Herkes:** "Join Network" → aynı ID'yi yapıştır → Host onaylar
4. Herkesin `10.x.x.x` şeklinde bir ZeroTier IP'si olur
5. Launcher'da bu IP'yi gir → normal LAN gibi çalışır

---

## ✅ Yama Listesi

| # | Değişiklik |
|---|-----------|
| 1 | PlayFab / Steam login → **bypass** |
| 2 | Sunucu kapalı kontrolü → **bypass** |
| 3 | Steam auth (DAULimitExceeded hatası) → **bypass** |
| 4 | Oyun içi isim → **Launcher'dan alınır** |
| 5 | **Tüm silahlar** kilitsiz |
| 6 | **Tüm mapler** kilitsiz |
| 7 | **Tüm bombalar** kilitsiz |
| 8 | **Pro** özellikler aktif (HP, Gravity, Wind vb.) |
| 9 | Tüm Weapon Pack / Map Pack → **sahip sayılır** |

---

## 🔧 Sorun Giderme

**Patch çalışmıyor / hata veriyor:**
```
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```
Yukarıdaki komutu PowerShell'de çalıştır, sonra patch.ps1'i tekrar dene.

**Oyun açılmıyor:**
- Steam'in arka planda açık olduğundan emin ol

**Host bağlanamıyor:**
- Windows Firewall'da 5127 (TCP) ve 50000 (UDP) portlarını aç:
```powershell
netsh advfirewall firewall add rule name="BrokenGround TCP" dir=in action=allow protocol=TCP localport=5127
netsh advfirewall firewall add rule name="BrokenGround UDP" dir=in action=allow protocol=UDP localport=50000
```

**Orijinal oyuna dönmek:**
- `BrokenGround_Data\Managed\Assembly-CSharp.dll.backup` dosyasını `Assembly-CSharp.dll` olarak yeniden adlandır

---

## ℹ️ Teknik Detaylar

- **Motor:** Unity 2018 (Mono)
- **Ağ:** TNet3 — TCP 5127 / UDP 50000
- **Bypass edilen:** PlayFab + Steam Auth + Photon
- **Araç:** Mono.Cecil (IL manipulation)

---

*Sadece özel kullanım içindir. Oyunu Steam'den satın almış olmanız gerekir.*
