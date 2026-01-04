import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart'; // RTDB
import 'package:dispenserapp/services/auth_service.dart';
import 'package:dispenserapp/services/notification_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dispenserapp/widgets/circular_selector.dart';
import 'package:dispenserapp/services/database_service.dart';
import 'package:dispenserapp/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeScreen extends StatefulWidget {
  final String macAddress;
  const HomeScreen({super.key, required this.macAddress});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final GlobalKey<CircularSelectorState> _circularSelectorKey = GlobalKey<CircularSelectorState>();

  final DatabaseService _databaseService = DatabaseService();
  final NotificationService _notificationService = NotificationService();
  final AuthService _authService = AuthService();

  final DatabaseReference _rtdbRef = FirebaseDatabase.instance.ref();

  List<Map<String, dynamic>> _sections = [];
  String _deviceName = "";
  bool _isLoading = true;
  bool _isRinging = false;
  DeviceRole _currentRole = DeviceRole.readOnly;
  bool _showHint = true;

  late AnimationController _fadeController;
  StreamSubscription<DocumentSnapshot>? _firestoreSubscription;
  StreamSubscription<DatabaseEvent>? _rtdbSubscription;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _initData();
    _checkHintStatus();
    // Bu senkronizasyon kritik!
    _startRTDBSyncListener();
  }

  @override
  void dispose() {
    _firestoreSubscription?.cancel();
    _rtdbSubscription?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _checkHintStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _showHint = !(prefs.getBool('has_seen_wheel_hint') ?? false);
      });
    }
  }

  void _dismissHint() {
    if (!_showHint) return;
    setState(() => _showHint = false);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('has_seen_wheel_hint', true);
    });
  }

  // --- KRİTİK DÜZELTME: GÜÇLÜ SENKRONİZASYON ---
  // ESP32 -> RTDB -> FLUTTER -> FIRESTORE
  void _startRTDBSyncListener() {
    String path = 'dispensers/${widget.macAddress}/config';
    print("RTDB Dinleniyor: $path");

    _rtdbSubscription = _rtdbRef.child(path).onValue.listen((event) {
      final snapshotValue = event.snapshot.value;

      if (snapshotValue != null && snapshotValue is Map) {
        // Gelen veriyi güvenli bir Map'e çevir
        Map<dynamic, dynamic> data = snapshotValue;

        // Bölmeleri gez
        data.forEach((key, value) {
          if (value is Map && key.toString().startsWith("section_")) {
            // Anahtar: section_0, section_1...
            int index = int.tryParse(key.toString().replaceAll("section_", "")) ?? -1;

            // Eğer geçerli bir bölme ve bizde o bölme varsa
            if (index >= 0 && index < _sections.length) {
              int rtdbPillCount = -1;

              // int olarak parse etmeyi dene
              if (value['pillCount'] is int) {
                rtdbPillCount = value['pillCount'];
              } else if (value['pillCount'] is String) {
                rtdbPillCount = int.tryParse(value['pillCount']) ?? -1;
              }

              // Firestore'dan gelen (Ekranda gözüken) veri
              int currentAppPillCount = _sections[index]['pillCount'] ?? 0;

              // EĞER FARK VARSA GÜNCELLE
              if (rtdbPillCount != -1 && rtdbPillCount != currentAppPillCount) {
                print(">>> STOK FARKI TESPİT EDİLDİ! <<<");
                print("Bölme $index: RTDB($rtdbPillCount) != App($currentAppPillCount)");
                print("Firestore güncelleniyor...");

                // 1. Ekranı hemen güncelle (Kullanıcı beklemesin)
                if (mounted) {
                  setState(() {
                    _sections[index]['pillCount'] = rtdbPillCount;
                  });
                }

                // 2. Firestore'u arkada güncelle (Kalıcı olması için)
                // Rol kontrolü: Sadece yetkili kişiler yazabilsin
                if (_currentRole == DeviceRole.owner || _currentRole == DeviceRole.secondary) {
                  _databaseService.updatePillCountOnly(widget.macAddress, index, rtdbPillCount);
                }
              }
            }
          }
        });
      }
    }, onError: (e) {
      print("RTDB Listener Error: $e");
    });
  }

  Future<void> _initData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final user = await _authService.getOrCreateUser();
    if (user != null) {
      _currentRole = await _databaseService.getUserRole(widget.macAddress, user.email);
    }

    // Firestore Dinleyici (Ana Veri Kaynağı)
    _firestoreSubscription = FirebaseFirestore.instance
        .collection('dispenser')
        .doc(widget.macAddress)
        .snapshots()
        .listen((doc) {
      if (mounted && doc.exists && doc.data() != null) {
        _processData(doc.data()!);
      }
    }, onError: (e) {
      debugPrint("Firestore Stream Hatası: $e");
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _processData(Map<String, dynamic> data) {
    String fetchedName = data['device_name'] ?? 'default_device_name'.tr();

    if (!data.containsKey('section_config')) {
      if (mounted) {
        setState(() {
          _deviceName = fetchedName;
          _sections = List.generate(3, (index) => {
            'name': 'medicine_default_name'.tr(args: [(index + 1).toString()]),
            'times': [TimeOfDay(hour: (8 + 5 * index) % 24, minute: 0)],
            'isActive': true,
            'pillCount': 0,
          });
          _isLoading = false;
        });
        _fadeController.forward();
      }
      return;
    }

    final List<dynamic> configData = data['section_config'];

    final List<Map<String, dynamic>> newSections = configData.map((item) {
      final Map<String, dynamic> section = item as Map<String, dynamic>;
      List<TimeOfDay> times = [];

      if (section.containsKey('schedule')) {
        times = (section['schedule'] as List).map((t) => TimeOfDay(hour: t['h'], minute: t['m'])).toList();
      } else if (section['isActive'] == true) {
        times.add(TimeOfDay(hour: section['hour'] ?? 8, minute: section['minute'] ?? 0));
      }

      if (times.isEmpty && section['isActive'] == true) {
        times.add(const TimeOfDay(hour: 8, minute: 0));
      }

      return {
        'name': section['name'] ?? 'medicine_default_name'.tr(),
        'times': times,
        'isActive': section['isActive'] ?? false,
        'pillCount': section['pillCount'] ?? 0,
      };
    }).toList();

    if (mounted) {
      setState(() {
        _deviceName = fetchedName;
        _sections = newSections;
        _isLoading = false;
      });
      _fadeController.forward();
      _notificationService.scheduleMedicationNotifications(context, _sections, widget.macAddress);
    }
  }

  Future<void> _saveSectionConfig() async {
    if (!_canEdit()) return;

    final List<Map<String, dynamic>> serializableList = _sections.map((section) {
      final List<TimeOfDay> times = section['times'] as List<TimeOfDay>;
      return {
        'name': section['name'],
        'isActive': section['isActive'],
        'pillCount': section['pillCount'],
        'schedule': times.map((t) => {'h': t.hour, 'm': t.minute}).toList(),
        'hour': times.isNotEmpty ? times.first.hour : 0,
        'minute': times.isNotEmpty ? times.first.minute : 0,
      };
    }).toList();

    await _databaseService.saveSectionConfig(widget.macAddress, serializableList);
  }

  Future<void> _handleBuzzer() async {
    if (!mounted) return;
    try {
      bool targetState = !_isRinging;
      setState(() => _isRinging = targetState);
      await _databaseService.toggleBuzzer(widget.macAddress, targetState);

      if (targetState) {
        Future.delayed(const Duration(seconds: 3), () async {
          if (mounted && _isRinging) {
            setState(() => _isRinging = false);
            await _databaseService.toggleBuzzer(widget.macAddress, false);
          }
        });
      }
    } catch (e) {
      debugPrint("Buzzer error: $e");
    }
  }

  bool _canEdit() => _currentRole == DeviceRole.owner || _currentRole == DeviceRole.secondary;

  void _showSuccessSnackbar() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        content: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.deepSea.withOpacity(0.9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.skyBlue, size: 22),
              const SizedBox(width: 12),
              Text("alarm_settings_saved".tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.skyBlue),
            const SizedBox(width: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.deepSea, fontSize: 18)),
          ],
        ),
        content: Text(content, style: const TextStyle(height: 1.5, fontSize: 15)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text("close".tr()))],
      ),
    );
  }

  void _showEditNameDialog() {
    final TextEditingController controller = TextEditingController(text: _deviceName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("edit_device_name".tr(), style: const TextStyle(color: AppColors.deepSea, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: "default_device_name".tr(),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("cancel".tr(), style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.skyBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _databaseService.updateDeviceName(widget.macAddress, controller.text.trim());
              }
              Navigator.pop(context);
            },
            child: Text("save".tr(), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceNameSection(bool isReadOnly) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              _deviceName.isEmpty ? "loading".tr() : _deviceName,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.deepSea,
                letterSpacing: 0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!isReadOnly) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit_rounded, color: AppColors.skyBlue, size: 20),
              onPressed: _showEditNameDialog,
              tooltip: "edit_name_tooltip".tr(),
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(4),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.skyBlue.withOpacity(0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ]
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReadOnly = !_canEdit();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        title: Text("device_settings_title".tr(), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.deepSea)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.deepSea),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FadeTransition(
        opacity: _fadeController,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            children: [
              _buildQuickActionButtons(),
              const SizedBox(height: 16),

              AnimatedSize(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutQuart,
                child: _showHint
                    ? Column(
                  children: [
                    _buildStatusHeader(isReadOnly),
                    const SizedBox(height: 30),
                  ],
                )
                    : const SizedBox.shrink(),
              ),

              if (!_showHint) const SizedBox(height: 15),

              _buildCircularSelector(isReadOnly),
              _buildDeviceNameSection(isReadOnly),

              const SizedBox(height: 25),

              if (!isReadOnly) _buildBuzzerButton(),
              const SizedBox(height: 35),

              _buildSectionHeader(),
              const SizedBox(height: 15),

              ..._sections.asMap().entries.map((e) => _buildMedicineCard(e.key, e.value, isReadOnly, theme)).toList(),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
            "scheduled_meds_title",
            style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.deepSea, fontSize: 17)
        ).tr(),
      ),
    );
  }

  Widget _buildQuickActionButtons() {
    return Row(
      children: [
        if (_currentRole == DeviceRole.owner)
          Expanded(
            child: _buildSmallActionButton(
              icon: Icons.manage_accounts_rounded,
              label: "access_management".tr(),
              color: AppColors.skyBlue,
              onTap: _showUserManagementDialog,
            ),
          ),
        if (_currentRole == DeviceRole.owner) const SizedBox(width: 10),

        Expanded(
          child: _buildSmallActionButton(
            icon: Icons.alarm_rounded,
            label: "alarm_settings".tr(),
            color: AppColors.deepSea,
            onTap: _showNotificationSettingsDialog,
          ),
        ),
      ],
    );
  }

  Widget _buildSmallActionButton({required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return Container(
      height: 85,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(height: 8),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.deepSea, fontWeight: FontWeight.w800, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusHeader(bool isReadOnly) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isReadOnly ? [Colors.orange.shade400, Colors.orange.shade700] : [AppColors.skyBlue, AppColors.deepSea],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: (isReadOnly ? Colors.orange : AppColors.deepSea).withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        children: [
          Icon(isReadOnly ? Icons.lock_person_rounded : Icons.tips_and_updates_outlined, color: Colors.white, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              isReadOnly ? "read_only_banner".tr() : "home_hint_text".tr(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularSelector(bool isReadOnly) {
    return Center(
      child: TweenAnimationBuilder(
        tween: Tween<double>(begin: 0.85, end: 1.0),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutBack,
        builder: (context, double value, child) => Transform.scale(
          scale: value,
          child: Container(
            height: MediaQuery.of(context).size.width * 0.78,
            width: MediaQuery.of(context).size.width * 0.78,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F7FA),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: AppColors.skyBlue.withOpacity(0.1), spreadRadius: 6, blurRadius: 25)],
            ),
            child: AbsorbPointer(
              absorbing: isReadOnly,
              child: Listener(
                onPointerDown: (_) => _dismissHint(),
                child: CircularSelector(
                    key: _circularSelectorKey,
                    sections: _sections,
                    onUpdate: (i, d) {
                      setState(() {
                        _sections[i]['name'] = d['name'];
                        _sections[i]['times'] = d['times'];
                        _sections[i]['pillCount'] = d['pillCount'];
                        _sections[i]['isActive'] = true;
                      });
                      _saveSectionConfig();
                    }
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBuzzerButton() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 200),
        child: SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _handleBuzzer,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isRinging ? Colors.redAccent : Colors.white,
              foregroundColor: _isRinging ? Colors.white : AppColors.deepSea,
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              padding: const EdgeInsets.symmetric(horizontal: 32),
            ),
            icon: Icon(_isRinging ? Icons.notifications_off_rounded : Icons.campaign_rounded, size: 24),
            label: Text(_isRinging ? "stop_sound".tr() : "find_device".tr(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          ),
        ),
      ),
    );
  }

  Widget _buildMedicineCard(int index, Map<String, dynamic> section, bool isReadOnly, ThemeData theme) {
    final List<TimeOfDay> times = section['times'] as List<TimeOfDay>;
    final bool isActive = section['isActive'];
    final int count = section['pillCount'] ?? 0;
    times.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));

    bool isCritical = (count <= 1 && isActive);
    bool isLow = (count < times.length && count > 1 && isActive);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: isCritical
            ? [BoxShadow(color: Colors.red.withOpacity(0.15), blurRadius: 15, offset: const Offset(0, 4))]
            : [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
        border: isCritical ? Border.all(color: Colors.redAccent.withOpacity(0.4), width: 1) : null,
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(24),
          child: ExpansionTile(
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            collapsedShape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Stack(
              children: [
                Image.asset('assets/single_pill.png', width: 34, height: 34, errorBuilder: (c, e, s) => const Icon(Icons.medication)),

                if(isActive)
                  Positioned(
                      right: 0, bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            color: isCritical ? Colors.redAccent : (isLow ? Colors.orangeAccent : AppColors.skyBlue),
                            shape: BoxShape.circle
                        ),
                        child: Text(
                            count.toString(),
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)
                        ),
                      )
                  )
              ],
            ),
            title: Row(
              children: [
                Text(section['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.deepSea)),
                if (isCritical)
                  const Padding(
                    padding: EdgeInsets.only(left: 8.0),
                    child: Icon(Icons.warning_amber_rounded, size: 20, color: Colors.redAccent),
                  ),
              ],
            ),
            subtitle: Text(
                isActive
                    ? "${times.length} ${'times_a_day'.tr()} • $count ${'left_abbr'.tr()}"
                    : "passive".tr(),
                style: TextStyle(
                    color: isActive ? (isCritical ? Colors.redAccent : AppColors.skyBlue) : Colors.grey,
                    fontSize: 13,
                    fontWeight: FontWeight.w600
                )
            ),
            trailing: isReadOnly ? const Icon(Icons.lock, size: 18, color: Colors.grey) : Switch.adaptive(
                value: isActive,
                activeColor: AppColors.skyBlue,
                onChanged: (v) {
                  setState(() => _sections[index]['isActive'] = v);
                  _saveSectionConfig();
                }
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  children: [
                    Container(height: 1, color: AppColors.skyBlue.withOpacity(0.1)),
                    const SizedBox(height: 18),
                    if (isActive) ...[
                      Wrap(spacing: 8, runSpacing: 8, children: times.map((t) => _buildTimeChip(t)).toList()),
                      const SizedBox(height: 20),
                      if (!isReadOnly)
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: () => _circularSelectorKey.currentState?.showEditDialog(index),
                            icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                            label: Text("edit_schedule".tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.skyBlue,
                                backgroundColor: AppColors.skyBlue.withOpacity(0.05),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                            ),
                          ),
                        ),
                    ] else Text("passive_desc".tr(), style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeChip(TimeOfDay time) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.skyBlue.withOpacity(0.15))
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.access_time_filled_rounded, size: 16, color: AppColors.skyBlue),
          const SizedBox(width: 8),
          Text(time.format(context), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.deepSea, fontSize: 15)),
        ],
      ),
    );
  }

  void _showUserManagementDialog() {
    final TextEditingController emailController = TextEditingController();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => const SizedBox(),
      transitionBuilder: (context, anim1, anim2, child) => Transform.scale(
        scale: Curves.easeOutBack.transform(anim1.value),
        child: Opacity(
          opacity: anim1.value,
          child: AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("access_management".tr(), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.deepSea, fontSize: 18)),
                IconButton(icon: const Icon(Icons.help_outline_rounded, color: AppColors.skyBlue), onPressed: () => _showInfoDialog("access_info_title".tr(), "access_info_desc".tr())),
              ],
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(
                      hintText: "user_email_hint".tr(),
                      prefixIcon: const Icon(Icons.email_outlined, size: 20),
                      suffixIcon: IconButton(icon: const Icon(Icons.add_circle, color: AppColors.skyBlue, size: 30), onPressed: () {
                        if (emailController.text.isNotEmpty) {
                          _databaseService.addReadOnlyUser(widget.macAddress, emailController.text.trim());
                          emailController.clear();
                        }
                      }),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      filled: true,
                      fillColor: AppColors.background,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(thickness: 0.5),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
                    child: StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('dispenser').doc(widget.macAddress).snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                        final data = snapshot.data!.data() as Map<String, dynamic>;
                        final readOnly = List<String>.from(data['read_only_mails'] ?? []);
                        final secondary = List<String>.from(data['secondary_mails'] ?? []);
                        return ListView(
                          shrinkWrap: true,
                          children: [
                            ...readOnly.map((e) => _buildUserRow(e, "viewer".tr(), Icons.visibility, Colors.grey, () => _databaseService.promoteToSecondary(widget.macAddress, e))),
                            ...secondary.map((e) => _buildUserRow(e, "admin".tr(), Icons.admin_panel_settings, AppColors.skyBlue, () => _databaseService.demoteToReadOnly(widget.macAddress, e))),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text("close".tr(), style: const TextStyle(fontWeight: FontWeight.bold)))],
          ),
        ),
      ),
    );
  }

  Widget _buildUserRow(String email, String role, IconData icon, Color color, VoidCallback onSwap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), radius: 18, child: Icon(icon, color: color, size: 18)),
        title: Text(email, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Text(role, style: TextStyle(color: color, fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.swap_horiz, color: Colors.blueAccent, size: 22), onPressed: onSwap),
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22), onPressed: () => _databaseService.removeUser(widget.macAddress, email)),
          ],
        ),
      ),
    );
  }

  Future<void> _showNotificationSettingsDialog() async {
    final user = await _authService.getOrCreateUser();
    if (user == null) return;

    final settings = await _notificationService.getNotificationSettings();
    bool alarmsEnabled = settings['alarms_enabled'] ?? true;
    bool notificationsEnabled = settings['notifications_enabled'] ?? true;
    int offset = settings['offset'] ?? 10;

    bool feedbackEnabled = await _databaseService.getDeviceFeedbackPreference(user.uid, widget.macAddress);

    if (!mounted) return;

    final List<int> offsetOptions = [0, 5, 10, 15, 30, 60];

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) => const SizedBox(),
      transitionBuilder: (context, anim1, anim2, child) => Transform.scale(
        scale: Curves.easeOutBack.transform(anim1.value),
        child: Opacity(
          opacity: anim1.value,
          child: StatefulBuilder(
            builder: (context, setSt) => AlertDialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("alarm_settings".tr(), style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.deepSea, fontSize: 18)),
                  IconButton(icon: const Icon(Icons.help_outline_rounded, color: AppColors.skyBlue), onPressed: () => _showInfoDialog("alarm_info_title".tr(), "alarm_settings_desc".tr())),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSettingsCard(
                      icon: Icons.alarm_on_rounded,
                      title: "exact_alarm_title".tr(),
                      subtitle: "exact_alarm_desc".tr(),
                      trailing: Switch.adaptive(value: alarmsEnabled, activeColor: AppColors.skyBlue, onChanged: (v) => setSt(() => alarmsEnabled = v)),
                    ),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(thickness: 0.5)),
                    _buildSettingsCard(
                      icon: Icons.notifications_active_outlined,
                      title: "pre_notification_title".tr(),
                      subtitle: "pre_notification_desc".tr(),
                      trailing: Switch.adaptive(value: notificationsEnabled, activeColor: AppColors.skyBlue, onChanged: (v) => setSt(() => notificationsEnabled = v)),
                    ),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(thickness: 0.5)),

                    _buildSettingsCard(
                      icon: Icons.feedback_outlined,
                      title: "responsive_feedback_title".tr(),
                      subtitle: feedbackEnabled ? "responsive_feedback_active".tr() : "responsive_feedback_inactive".tr(),
                      trailing: Switch.adaptive(
                          value: feedbackEnabled,
                          activeColor: AppColors.skyBlue,
                          onChanged: (v) => setSt(() => feedbackEnabled = v)
                      ),
                    ),

                    if (notificationsEnabled) ...[
                      const SizedBox(height: 24),
                      Text("notification_offset_label".tr(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.deepSea)),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 2.2,
                        ),
                        itemCount: offsetOptions.length,
                        itemBuilder: (context, index) {
                          final val = offsetOptions[index];
                          final isSelected = offset == val;
                          return GestureDetector(
                            onTap: () => setSt(() => offset = val),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.skyBlue : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isSelected ? AppColors.skyBlue : Colors.grey.shade300, width: 1.5),
                                boxShadow: isSelected ? [BoxShadow(color: AppColors.skyBlue.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))] : [],
                              ),
                              child: Text(
                                val == 0 ? "exact_time_label".tr() : "$val ${"minutes_unit".tr()}",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: isSelected ? Colors.white : AppColors.deepSea, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text("cancel".tr(), style: const TextStyle(color: Colors.grey))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.skyBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10)),
                  onPressed: () async {
                    await _notificationService.saveNotificationSettings(alarmsEnabled: alarmsEnabled, notificationsEnabled: notificationsEnabled, offset: offset);
                    await _databaseService.saveDevicePreference(user.uid, widget.macAddress, feedbackEnabled);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('feedback_enabled', feedbackEnabled);

                    if (mounted) {
                      await _notificationService.scheduleMedicationNotifications(context, _sections, widget.macAddress);
                      Navigator.pop(context);
                      _showSuccessSnackbar();
                    }
                  },
                  child: Text("save".tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsCard({required IconData icon, required String title, required String subtitle, required Widget trailing}) {
    return Row(
      children: [
        CircleAvatar(backgroundColor: AppColors.skyBlue.withOpacity(0.1), radius: 22, child: Icon(icon, color: AppColors.skyBlue, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.deepSea)),
          Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.2)),
        ])),
        trailing,
      ],
    );
  }
}