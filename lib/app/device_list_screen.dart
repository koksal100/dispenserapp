import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/database_service.dart';
import 'home_screen.dart';

class DeviceListScreen extends StatefulWidget {
  final bool isDragMode;
  final Function(bool) onModeChanged;

  const DeviceListScreen({
    super.key,
    required this.isDragMode,
    required this.onModeChanged,
  });

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  late Future<AppUser?> _initAndPrecacheFuture;
  final AuthService _authService = AuthService();
  final DatabaseService _dbService = DatabaseService();
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _isInitialized = true;
      _initAndPrecacheFuture = _initialize();
    }
  }

  Future<AppUser?> _initialize() async {
    final results = await Future.wait([
      _authService.getOrCreateUser(),
      precacheImage(const AssetImage('assets/dispenser_icon.png'), context),
    ]);
    return results[0] as AppUser?;
  }

  void _retryLogin() {
    setState(() {
      _initAndPrecacheFuture = _initialize();
    });
  }

  // --- Yardımcı Diyaloglar ---
  void _showAddDeviceDialog(String uid, String userEmail) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: Text("manual_add_title").tr(),
            content: TextField(
              controller: controller,
              keyboardType: TextInputType.visiblePassword,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-fA-F0-9]')),
                MacAddressInputFormatter(),
                LengthLimitingTextInputFormatter(17),
              ],
              decoration: InputDecoration(
                labelText: "mac_address".tr(),
                hintText: 'AA:BB:CC:11:22:33',
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("cancel".tr()),
              ),
              ElevatedButton(
                onPressed: () async {
                  final mac = controller.text.trim();
                  if (mac.length == 17) {
                    if (userEmail.isEmpty) return;
                    final result = await _dbService.addDeviceManually(
                        uid, userEmail, mac);
                    if (!mounted) return;
                    Navigator.pop(context);
                    if (result == 'success') {
                      await _dbService.updateUserDeviceList(uid, userEmail);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("device_added_success".tr())),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text(result), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                child: Text("add".tr()),
              ),
            ],
          ),
    );
  }

  void _showEditNameDialog(String macAddress, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: Text("edit_device_name".tr()),
            content: TextField(controller: controller, autofocus: true),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("cancel".tr()),
              ),
              ElevatedButton(
                onPressed: () {
                  if (controller.text.isNotEmpty) _dbService.updateDeviceName(
                      macAddress, controller.text.trim());
                  Navigator.pop(context);
                },
                child: Text("save".tr()),
              ),
            ],
          ),
    );
  }

  void _showRenameGroupDialog(String uid, String groupId, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: Text("edit_room_name".tr()),
            content: TextField(controller: controller, autofocus: true),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text("cancel".tr()),
              ),
              ElevatedButton(
                onPressed: () {
                  if (controller.text.isNotEmpty) _dbService.renameGroup(
                      uid, groupId, controller.text.trim());
                  Navigator.pop(context);
                },
                child: Text("save".tr()),
              )
            ],
          ),
    );
  }

  void _showDeleteConfirmDialog(String uid, String groupId) {
    showDialog(
      context: context,
      builder: (c) =>
          AlertDialog(
            title: Text("delete_room_title".tr()),
            content: Text("delete_room_desc".tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text("cancel".tr()),
              ),
              TextButton(
                onPressed: () {
                  _dbService.deleteGroup(uid, groupId);
                  Navigator.pop(c);
                },
                child: Text(
                  "delete".tr(),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  void _showHideDeviceDialog(String uid, String deviceId) {
    showDialog(
      context: context,
      builder: (ctx) =>
          AlertDialog(
            title: Text("hide_device_title".tr()),
            content: Text("hide_device_desc".tr()),
            actions: [
              TextButton(
                child: Text("cancel".tr()),
                onPressed: () => Navigator.pop(ctx),
              ),
              TextButton(
                child: Text(
                  "remove".tr(),
                  style: const TextStyle(color: Colors.red),
                ),
                onPressed: () {
                  _dbService.hideDevice(uid, deviceId);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: _initAndPrecacheFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError || snapshot.data == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("login_failed".tr()),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _retryLogin,
                  child: Text("retry".tr()),
                ),
              ],
            ),
          );
        }

        final userData = snapshot.data!;
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: _buildDeviceList(userData.uid),
          floatingActionButton: !widget.isDragMode
              ? FloatingActionButton(
            onPressed: () =>
                _showAddDeviceDialog(userData.uid, userData.email ?? ''),
            backgroundColor: Theme
                .of(context)
                .colorScheme
                .secondary, // Turkuaz Vurgu
            child: const Icon(Icons.add, color: Colors.white),
            tooltip: "manual_add_title".tr(),
          )
              : null,
        );
      },
    );
  }

  Widget _buildDeviceList(String uid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, userSnapshot) {
        if (!userSnapshot.hasData || !userSnapshot.data!.exists)
          return const CircularProgressIndicator();

        final userData = userSnapshot.data!.data() as Map<String, dynamic>;

        final List<dynamic> unvisibleList = userData['unvisible_devices'] ?? [];
        bool isVisible(dynamic mac) => !unvisibleList.contains(mac.toString());

        final List<dynamic> owned = (userData['owned_dispensers'] ?? []).where(
            isVisible).toList();
        final List<dynamic> secondary = (userData['secondary_dispensers'] ?? [])
            .where(isVisible)
            .toList();
        final List<dynamic> readOnly = (userData['read_only_dispensers'] ?? [])
            .where(isVisible)
            .toList();
        final List<dynamic> deviceGroups = userData['device_groups'] ?? [];

        final List<Map<String, dynamic>> allDevices = [];
        for (var mac in owned)
          allDevices.add({'mac': mac, 'role': 'owner'});
        for (var mac in secondary)
          if (!allDevices.any((d) => d['mac'] == mac)) allDevices.add(
              {'mac': mac, 'role': 'secondary'});
        for (var mac in readOnly)
          if (!allDevices.any((d) => d['mac'] == mac)) allDevices.add(
              {'mac': mac, 'role': 'readOnly'});

        if (allDevices.isEmpty && deviceGroups.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                "no_devices".tr(),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        Set<String> groupedMacs = {};
        for (var group in deviceGroups) {
          List<dynamic> devices = group['devices'] ?? [];
          for (var d in devices)
            groupedMacs.add(d.toString());
        }

        List<Map<String, dynamic>> ungroupedDevices = allDevices
            .where((device) => !groupedMacs.contains(device['mac']))
            .toList();

        return DragTarget<String>(
          onWillAccept: (data) => widget.isDragMode && data != null,
          onAccept: (macAddress) {
            _dbService.moveDeviceToGroup(uid, macAddress, "");
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("device_moved_main".tr())),
            );
          },
          builder: (context, candidateData, rejectedData) {
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              color: candidateData.isNotEmpty
                  ? Colors.red.withOpacity(0.05)
                  : Colors.transparent,
              child: ListView(
                padding: const EdgeInsets.only(
                    top: 20.0, bottom: 80, left: 16, right: 16),
                children: [
                  // Bilgi Kartı
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    crossFadeState: widget.isDragMode
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    firstChild: Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.touch_app, color: Colors.amber.shade800),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "drag_instruction".tr(),
                              style: TextStyle(
                                  color: Colors.amber.shade900, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    secondChild: const SizedBox(width: double.infinity),
                  ),

                  // KLASÖRLER
                  ...deviceGroups.map((group) =>
                      _buildGroupCard(uid, group, allDevices)).toList(),

                  const SizedBox(height: 10),

                  // DİĞER CİHAZLAR BAŞLIĞI
                  if (deviceGroups.isNotEmpty && ungroupedDevices.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8.0, horizontal: 4),
                      child: Text(
                        "other_devices".tr(),
                        style: TextStyle(fontWeight: FontWeight.bold,
                            color: Colors.blueGrey.shade600,
                            fontSize: 16),
                      ),
                    ),

                  // CİHAZLAR
                  ...ungroupedDevices.map((device) {
                    return _buildDraggableOrNormalCard(
                        uid, device['mac'], device['role'],
                        isInsideGroup: false);
                  }).toList(),

                  const SizedBox(height: 150),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --- KLASÖR KARTI  ---
  Widget _buildGroupCard(String uid, Map<String, dynamic> group, List<Map<String, dynamic>> allDevices) {
    String groupId = group['id'] ?? "";
    String groupName = group['name'];
    List<dynamic> groupMacs = group['devices'] ?? [];
    List<dynamic> visibleGroupMacs = groupMacs.where((mac) => allDevices.any((d) => d['mac'] == mac)).toList();

    Widget cardContent = Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blueGrey.shade50, width: 1),
      ),
      child: InkWell(
        onLongPress: () => widget.onModeChanged(true),
        borderRadius: BorderRadius.circular(16),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: widget.isDragMode,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), // Dikey boşluk hafif artırıldı
            childrenPadding: const EdgeInsets.only(bottom: 12),
            leading: Container(
              padding: const EdgeInsets.all(8), // İkon alanı hafif genişletildi
              decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
              child: Icon(Icons.folder_open_rounded, color: Colors.orange.shade800, size: 24),
            ),

            // --- GÜNCELLEME BURADA ---
            // Başlık fontu 15'ten 18'e çıkarıldı (Dışarıdaki cihazlarla birebir aynı oldu)
            title: Text(
                groupName,
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18, // GÜNCELLENDİ
                    color: Color(0xFF0F5191) // Derin Deniz Mavisi
                )
            ),

            subtitle: Text("${visibleGroupMacs.length} ${"device_count_suffix".tr()}",
                style: TextStyle(color: Colors.blueGrey.shade400, fontSize: 12)),
            trailing: widget.isDragMode
                ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue, size: 22),
                  onPressed: () => _showRenameGroupDialog(uid, groupId, groupName),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                  onPressed: () => _showDeleteConfirmDialog(uid, groupId),
                ),
              ],
            )
                : null,
            children: visibleGroupMacs.map((mac) {
              var deviceEntry = allDevices.firstWhere((d) => d['mac'] == mac, orElse: () => {'mac': mac, 'role': 'unknown'});
              return _buildDraggableOrNormalCard(uid, mac.toString(), deviceEntry['role'], isInsideGroup: true);
            }).toList(),
          ),
        ),
      ),
    );

    if (widget.isDragMode) {
      return DragTarget<String>(
        onWillAccept: (data) => data != null,
        onAccept: (macAddress) {
          _dbService.moveDeviceToGroup(uid, macAddress, groupId);
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("device_moved_room".tr(args: [groupName])),
              duration: const Duration(milliseconds: 800),
            ),
          );
        },
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack,
            tween: Tween<double>(begin: 1.0, end: isHovering ? 1.02 : 1.0),
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  color: Colors.transparent,
                  child: cardContent,
                ),
              );
            },
          );
        },
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: cardContent,
    );
  }

  Widget _buildDraggableOrNormalCard(String uid, String macAddress, String role,
      {required bool isInsideGroup}) {
    Widget card = _buildDeviceCardUI(
      uid,
      macAddress,
      role,
      isInsideGroup: isInsideGroup,
      interactive: !widget.isDragMode,
      onLongPress: () {},
    );

    return LongPressDraggable<String>(
      data: macAddress,
      delay: const Duration(milliseconds: 300),
      onDragStarted: () {
        if (!widget.isDragMode) {
          widget.onModeChanged(true);
        }
      },
      childWhenDragging: Opacity(opacity: 0.3, child: card),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: MediaQuery
              .of(context)
              .size
              .width * 0.85,
          child: Card(
            elevation: 10,
            color: Colors.white.withOpacity(0.95),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.drag_indicator, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "${"moving".tr()}: $macAddress",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      child: card,
    );
  }

// --- MODERN & MARKALI CİHAZ KARTI UI (HİZALAMA VE BOYUT DÜZELTİLDİ) ---
  Widget _buildDeviceCardUI(String uid, String macAddress, String role,
      {required bool isInsideGroup, required bool interactive, required VoidCallback onLongPress}) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('dispenser')
          .doc(macAddress)
          .snapshots(),
      builder: (context, deviceSnapshot) {
        String deviceName = "loading".tr();
        bool exists = false;

        if (deviceSnapshot.hasData && deviceSnapshot.data!.exists) {
          final data = deviceSnapshot.data!.data() as Map<String, dynamic>;
          deviceName = data['device_name'] ?? "default_device_name".tr();
          exists = true;
        }

        // --- BOYUT VE MARGIN AYARLARI (GÜNCELLENDİ) ---

        // Klasör içi yükseklik artırıldı: 85 -> 105 (Daha rahat okunur)
        final double cardHeight = isInsideGroup ? 105.0 : 130.0;

        // Klasör içi resim büyütüldü: 50 -> 60
        final double imageSize = isInsideGroup ? 60.0 : 85.0;

        // Klasör içi font büyütüldü: 14 -> 15.5
        final double titleFontSize = isInsideGroup ? 15.5 : 18.0;

        // MARGIN DÜZELTMESİ:
        // ListView zaten 16px padding veriyor.
        // Klasör dışındakilere (isInsideGroup=false) '0' vererek klasörle aynı hizaya getirdik.
        // Klasör içindekilere (isInsideGroup=true) '4' vererek hafif içeride durmasını sağladık (Hiyerarşi için).
        final double horizontalMargin = isInsideGroup ? 4.0 : 0.0;
        final double verticalMargin = isInsideGroup ? 4.0 : 8.0;

        Color roleBgColor;
        Color roleTextColor;
        String roleText;
        IconData roleIcon;

        const Color colorTurquoise = Color(0xFF36C0A6);
        const Color colorSkyBlue = Color(0xFF1D8AD6);
        const Color colorDeepSea = Color(0xFF0F5191);

        if (role == 'owner') {
          roleBgColor = colorTurquoise.withOpacity(0.12);
          roleTextColor = colorTurquoise;
          roleText = "owner".tr();
          roleIcon = Icons.verified_user_rounded;
        } else if (role == 'secondary') {
          roleBgColor = colorSkyBlue.withOpacity(0.12);
          roleTextColor = colorSkyBlue;
          roleText = "admin".tr();
          roleIcon = Icons.security_rounded;
        } else {
          roleBgColor = Colors.grey.shade100;
          roleTextColor = colorDeepSea.withOpacity(0.7);
          roleText = "viewer".tr();
          roleIcon = Icons.visibility_rounded;
        }

        return Container(
          height: cardHeight,
          width: double.infinity,
          margin: EdgeInsets.symmetric(
            vertical: verticalMargin,
            horizontal: horizontalMargin, // Düzeltilmiş kenar boşluğu
          ),
          child: Card(
            clipBehavior: Clip.antiAlias,
            // CardTheme main.dart'tan geliyor
            child: InkWell(
              onTap: (exists && interactive)
                  ? () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => HomeScreen(macAddress: macAddress)),
                );
              }
                  : null,
              onLongPress: onLongPress,
              child: Padding(
                // Klasör içi padding biraz daha ferahlatıldı (8 -> 10)
                padding: EdgeInsets.all(isInsideGroup ? 10.0 : 12.0),
                child: Row(
                  children: [
                    Container(
                      width: imageSize,
                      height: imageSize,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F9FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade50),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/dispenser_icon.png',
                          fit: BoxFit.cover,
                          errorBuilder: (c, o, s) =>
                              Icon(Icons.medication, color: colorSkyBlue,
                                  size: imageSize * 0.5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: roleBgColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Rol ikonu ve yazısı da büyütüldü
                                Icon(roleIcon, size: isInsideGroup ? 12 : 14,
                                    color: roleTextColor),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    roleText,
                                    style: TextStyle(
                                      color: roleTextColor,
                                      // Klasör içi rol yazısı 9 -> 11 oldu (Okunabilirlik arttı)
                                      fontSize: isInsideGroup ? 11 : 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: Text(
                              deviceName,
                              style: TextStyle(
                                color: colorDeepSea,
                                fontWeight: FontWeight.w700,
                                fontSize: titleFontSize, // 15.5 oldu
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              macAddress,
                              style: TextStyle(
                                color: Colors.blueGrey.shade400,
                                fontSize: isInsideGroup ? 11.5 : 12,
                                // Hafif büyütüldü
                                fontFamily: 'Courier',
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (widget.isDragMode)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            iconSize: isInsideGroup ? 22 : 24,
                            // Butonlar büyütüldü
                            constraints: const BoxConstraints(),
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.delete_outline_rounded,
                                color: Colors.redAccent),
                            onPressed: () =>
                                _showHideDeviceDialog(uid, macAddress),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.drag_indicator_rounded, color: Colors.grey,
                              size: isInsideGroup ? 22 : 24),
                        ],
                      )
                    else
                      if (role != 'readOnly' && interactive)
                        Icon(Icons.chevron_right_rounded,
                            color: Colors.blueGrey.shade200,
                            size: isInsideGroup ? 22 : 24),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class MacAddressInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text;
    text = text.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toUpperCase();
    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex % 2 == 0 && nonZeroIndex != text.length) {
        buffer.write(':');
      }
    }
    var string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}