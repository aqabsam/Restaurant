import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const String kBookedOrdersDbKey = 'booked_orders_v1';
const String kBookMenuDbKey = 'book_menu_sections_v1';
const String kBillDeskAlertsDbKey = 'bill_desk_alerts_v1';
const String kDeviceIdDbKey = 'restaurant_device_id_v1';
const String kCloudSyncCollection = 'restaurant_sync';
const String kCloudMenuDocument = 'book_menu';
const String kCloudBillDeskAlertsCollection = 'bill_desk_alerts';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _hydrateBookMenuSections();
  await _hydrateBookedOrders();
  await _hydrateBillDeskAlerts();
  runApp(const MyApp());
  unawaited(_safePostLaunchInit());
}

Future<void> _safePostLaunchInit() async {
  try {
    await _initLocalNotifications();
  } catch (_) {
    // Keep app running even if local notifications are unavailable.
  }
  try {
    await _startCloudMenuSync();
  } catch (_) {
    // Keep app running even if cloud sync is unavailable.
  }
  try {
    await _startCloudBillDeskAlertsSync();
  } catch (_) {
    // Keep app running even if cloud sync is unavailable.
  }
}

const String kRazorpayKey = 'rzp_test_your_key_here';
const String kBillMakerUser = '8986392298';
const String kBillMakerPass = 'aqab';
const String kMerchantUpiId = 'aqabs@ybl';
const int kBillMakerMaxLoginAttempts = 5;
const Duration kBillMakerLockoutDuration = Duration(minutes: 2);

final List<MenuSection> kHomeMenuSections = [
  MenuSection(
    title: 'Starter',
    items: [
      MenuItem(
        name: 'Crispy Spring Rolls',
        price: 149,
        imageUrl:
            'https://images.unsplash.com/photo-1625938144755-652e08e359b7?auto=format&fit=crop&w=900&q=80',
      ),
      MenuItem(
        name: 'Paneer Tikka',
        price: 199,
        imageUrl:
            'https://images.unsplash.com/photo-1567188040759-fb8a883dc6d8?auto=format&fit=crop&w=900&q=80',
      ),
      MenuItem(
        name: 'Garlic Bread',
        price: 129,
        imageUrl:
            'https://images.unsplash.com/photo-1603073163308-9654c3fb70b5?auto=format&fit=crop&w=900&q=80',
      ),
    ],
  ),
  MenuSection(
    title: 'Main Course',
    items: [
      MenuItem(
        name: 'Butter Chicken',
        price: 329,
        imageUrl:
            'https://images.unsplash.com/photo-1603894584373-5ac82b2ae398?auto=format&fit=crop&w=900&q=80',
      ),
      MenuItem(
        name: 'Veg Biryani',
        price: 269,
        imageUrl: _bookMenuImageFor('Veg Biryani'),
      ),
      MenuItem(
        name: 'Pasta Alfredo',
        price: 289,
        imageUrl: _bookMenuImageFor('Pasta Alfredo'),
      ),
    ],
  ),
  MenuSection(
    title: 'Desserts',
    items: [
      MenuItem(
        name: 'Chocolate Lava Cake',
        price: 189,
        imageUrl:
            'https://images.unsplash.com/photo-1617305855058-336d24456869?auto=format&fit=crop&w=900&q=80',
      ),
      MenuItem(
        name: 'Blueberry Cheesecake',
        price: 219,
        imageUrl:
            'https://images.unsplash.com/photo-1533134242443-d4fd215305ad?auto=format&fit=crop&w=900&q=80',
      ),
      MenuItem(
        name: 'Gulab Jamun',
        price: 129,
        imageUrl: _bookMenuImageFor('Gulab Jamun'),
      ),
    ],
  ),
];

List<MenuSection> get kOnlineMenuSections => kBookMenuSections.value
    .map(
      (section) => MenuSection(
        title: section.title,
        items: section.items
            .map(
              (item) => MenuItem(
                name: item.name,
                price: item.price ?? 0,
                imageUrl: _bookMenuImageForItem(item),
              ),
            )
            .toList(growable: false),
      ),
    )
    .toList(growable: false);

const List<BookMenuSection> kDefaultBookOrderSections = [
  BookMenuSection(
    title: 'Home Specials',
    items: [
      BookMenuItem(name: 'Crispy Spring Rolls', price: 149),
      BookMenuItem(name: 'Paneer Tikka', price: 199),
      BookMenuItem(name: 'Garlic Bread', price: 129),
      BookMenuItem(name: 'Butter Chicken', price: 329),
      BookMenuItem(name: 'Veg Biryani', price: 269),
      BookMenuItem(name: 'Pasta Alfredo', price: 289),
      BookMenuItem(name: 'Chocolate Lava Cake', price: 189),
      BookMenuItem(name: 'Blueberry Cheesecake', price: 219),
      BookMenuItem(name: 'Gulab Jamun', price: 129),
    ],
  ),
  BookMenuSection(
    title: 'Soups (Shorba)',
    items: [
      BookMenuItem(name: 'Hot & Sour Soup Chicken', price: 169),
      BookMenuItem(name: 'Hot & Sour Soup Veg', price: 156),
      BookMenuItem(name: 'Manchow Soup Chicken', price: 169),
      BookMenuItem(name: 'Manchow Soup Veg', price: 156),
      BookMenuItem(name: 'Shorba Veg', price: 156),
      BookMenuItem(name: 'Sweet Corn Soup Chicken', price: 169),
      BookMenuItem(name: 'Sweet Corn Soup Veg', price: 156),
    ],
  ),
  BookMenuSection(
    title: 'Veg Appetizers (Starters)',
    items: [
      BookMenuItem(name: 'Achhari Paneer Tikka', price: 325),
      BookMenuItem(name: 'Afghani Soya Chaap', price: 286),
      BookMenuItem(name: 'Asian Spring Roll (veg)', price: 234),
      BookMenuItem(name: 'Chilli Baby Corn Dry', price: 351),
      BookMenuItem(name: 'Chilly Mushroom', price: 285),
      BookMenuItem(name: 'Corn Salt & Pepper', price: 234),
      BookMenuItem(name: 'Cottage Cheese Chilli Dry', price: 312),
      BookMenuItem(name: 'Crispy Chilli Potato', price: 234),
      BookMenuItem(name: 'Haryali Paneer Tikka', price: 325),
      BookMenuItem(name: 'Khasta Kebab', price: 299),
      BookMenuItem(name: 'Momos Veg (fried)', price: 273),
      BookMenuItem(name: 'Momos Veg (steamed)', price: 234),
      BookMenuItem(name: 'Paneer Malai Tikka', price: 338),
      BookMenuItem(name: 'Paneer Tikka Shashlik', price: 325),
      BookMenuItem(name: 'Spicy Schezwan Cottage Cheese', price: 299),
      BookMenuItem(name: 'Tandoori Aloo', price: 286),
      BookMenuItem(name: 'Tandoori Guldosto', price: 559),
      BookMenuItem(name: 'Tandoori Soya Chaap', price: 273),
      BookMenuItem(name: 'Veg. Haryali Kebab', price: 286),
      BookMenuItem(name: 'Veg. Manchurian Dry', price: 234),
    ],
  ),
  BookMenuSection(
    title: 'Non-Veg Appetizers',
    items: [
      BookMenuItem(name: 'Afghan Chicken', price: 481),
      BookMenuItem(name: 'Asian Spring Roll Non-veg', price: 338),
      BookMenuItem(name: 'Chicken 65', price: 429),
      BookMenuItem(name: 'Chicken Sikh Kebab', price: 481),
      BookMenuItem(name: 'Malai Chicken Tikka', price: 481),
      BookMenuItem(name: 'Crispy Chilli Fish', price: 481),
      BookMenuItem(name: 'Crispy Honey Chicken', price: 442),
      BookMenuItem(name: 'Drums Of Heaven', price: 442),
      BookMenuItem(name: 'Chicken Fried Cheese Momos', price: 351),
      BookMenuItem(name: 'Grilled Tandoori Non-veg Platter', price: 956),
      BookMenuItem(name: 'Hunan Chilli Chicken Dry', price: 442),
      BookMenuItem(name: 'Lazeez Chicken Tikka', price: 481),
      BookMenuItem(name: 'Chicken Fried Momos', price: 338),
      BookMenuItem(name: 'Steamed Chicken Momos', price: 312),
      BookMenuItem(name: 'Mutton Sikh Kebab', price: 533),
      BookMenuItem(name: 'Prawn Tempura', price: 559),
      BookMenuItem(name: 'Prawns Pepper Salt', price: 559),
      BookMenuItem(name: 'Spicy Szechwan Chicken', price: 442),
      BookMenuItem(name: 'Chicken Szechwan Fried Momos', price: 351),
      BookMenuItem(name: 'Tandoori Chicken', price: 468),
      BookMenuItem(name: 'Tandoori Fish Tikka', price: 533),
      BookMenuItem(name: 'Tandoori Prawns', price: 819),
      BookMenuItem(name: 'Three Pepper Chicken In Dry Chilli', price: 442),
    ],
  ),
  BookMenuSection(
    title: 'Veg Main Course',
    items: [
      BookMenuItem(name: 'Aloo Jeera', price: 247),
      BookMenuItem(name: 'Dal Makhani', price: 299),
      BookMenuItem(name: 'Dal Tadka', price: 247),
      BookMenuItem(name: 'Dum Aloo Kashmiri', price: 273),
      BookMenuItem(name: 'Gobhi Masala', price: 247),
      BookMenuItem(name: 'Kadhai Paneer', price: 377),
      BookMenuItem(name: 'Malai Kofta', price: 338),
      BookMenuItem(name: 'Mixed Vegetable', price: 299),
      BookMenuItem(name: 'Mushroom Matar Hara Pyaz', price: 325),
      BookMenuItem(name: 'Paneer Butter Masala', price: 377),
      BookMenuItem(name: 'Paneer Lababdar', price: 377),
      BookMenuItem(name: 'Paneer Makhni', price: 377),
      BookMenuItem(name: 'Paneer Tika Masala', price: 377),
      BookMenuItem(name: 'Soya Chaap Masala', price: 325),
      BookMenuItem(name: 'Vegetable Kofta', price: 299),
    ],
  ),
  BookMenuSection(
    title: 'Non-Veg Main Course',
    items: [
      BookMenuItem(name: 'Butter Chicken', price: 559),
      BookMenuItem(name: 'Chicken Curry', price: 533),
      BookMenuItem(name: 'Chicken Lababdar', price: 618),
      BookMenuItem(name: 'Chicken Tikka Masala', price: 618),
      BookMenuItem(name: 'Fish Curry', price: 585),
      BookMenuItem(name: 'Goan Fish Curry', price: 585),
      BookMenuItem(name: 'Goan Prawn Curry', price: 611),
      BookMenuItem(name: 'Kadhai Chicken', price: 533),
      BookMenuItem(name: 'Kadhai Gosht', price: 572),
      BookMenuItem(name: 'Mutton Bhuna', price: 572),
      BookMenuItem(name: 'Prawn Curry', price: 611),
      BookMenuItem(name: 'Rahra Meat', price: 572),
      BookMenuItem(name: 'Rogan Josh', price: 572),
      BookMenuItem(name: 'Special Egg Curry', price: 273),
    ],
  ),
  BookMenuSection(
    title: 'Rice & Biryani',
    items: [
      BookMenuItem(name: 'Murgh Biryani', price: 408),
      BookMenuItem(name: 'Double Egg Biryani', price: 325),
      BookMenuItem(name: 'Gosht Biryani', price: 468),
      BookMenuItem(name: 'Jeera Rice', price: 169),
      BookMenuItem(name: 'Khuska', price: 182),
      BookMenuItem(name: 'Steamed Rice', price: 156),
      BookMenuItem(name: 'Tarkari Kesari Biryani', price: 299),
    ],
  ),
  BookMenuSection(
    title: 'Indian Breads',
    items: [
      BookMenuItem(name: 'Bread Basket', price: 273),
      BookMenuItem(name: 'Butter Naan', price: 65),
      BookMenuItem(name: 'Butter Roti', price: 33),
      BookMenuItem(name: 'Cheese Naan', price: 91),
      BookMenuItem(name: 'Garlic Naan', price: 78),
      BookMenuItem(name: 'Keema Naan', price: 117),
      BookMenuItem(name: 'Kulcha (mix)', price: 78),
      BookMenuItem(name: 'Kulcha (paneer)', price: 78),
      BookMenuItem(name: 'Missi Roti', price: 46),
      BookMenuItem(name: 'Naan', price: 52),
      BookMenuItem(name: 'Parantha (chilli)', price: 65),
      BookMenuItem(name: 'Parantha (laccha)', price: 65),
      BookMenuItem(name: 'Parantha (pudina)', price: 65),
      BookMenuItem(name: 'Tandoori Roti', price: 26),
    ],
  ),
  BookMenuSection(
    title: 'Desserts',
    items: [
      BookMenuItem(name: 'Butterscotch Ice Cream', price: 117),
      BookMenuItem(name: 'Chocolate Ice Cream', price: 117),
      BookMenuItem(name: 'Gulab Jamun', price: 91),
      BookMenuItem(name: 'Strawberry Ice Cream', price: 117),
      BookMenuItem(name: 'Vanilla Ice Cream', price: 117),
    ],
  ),
  BookMenuSection(
    title: 'Drinks (Beverages)',
    items: [
      BookMenuItem(name: 'Bottled Water [1L]', price: 26),
      BookMenuItem(name: 'Chocolate Milkshake', price: 169),
      BookMenuItem(name: 'Cold Coffee', price: 117),
      BookMenuItem(name: 'Lassi Salted', price: 117),
      BookMenuItem(name: 'Lassi Sweet', price: 117),
      BookMenuItem(name: 'Special Jaljeera', price: 78),
      BookMenuItem(name: 'Strawberry Milkshake', price: 169),
      BookMenuItem(name: 'Vanilla Milk Shake', price: 169),
    ],
  ),
  BookMenuSection(
    title: 'Mocktails',
    items: [
      BookMenuItem(name: 'Mint Mojito'),
      BookMenuItem(name: 'Blue Angle (tropical mocktail)'),
    ],
  ),
];

String _bookMenuImageFor(String itemName) {
  final lower = itemName.toLowerCase();
  if (lower.contains('soup') || lower.contains('shorba')) {
    return 'https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=900&q=80';
  }
  if (lower.contains('mutton') ||
      lower.contains('chicken') ||
      lower.contains('sikh kebab') ||
      lower.contains('kebab')) {
    return 'https://images.unsplash.com/photo-1527477396000-e27163b481c2?auto=format&fit=crop&w=900&q=80';
  }
  if (lower.contains('fish') || lower.contains('prawn')) {
    return 'https://images.unsplash.com/photo-1559847844-5315695dadae?auto=format&fit=crop&w=900&q=80';
  }
  if (lower.contains('biryani') ||
      lower.contains('rice') ||
      lower.contains('khuska')) {
    return 'https://images.unsplash.com/photo-1633945274405-b6c8069047b0?auto=format&fit=crop&w=900&q=80';
  }
  if (lower.contains('pasta') || lower.contains('alfredo')) {
    return 'https://images.unsplash.com/photo-1555949258-eb67b1ef0ceb?auto=format&fit=crop&w=900&q=80';
  }
  if (lower.contains('naan') ||
      lower.contains('roti') ||
      lower.contains('kulcha') ||
      lower.contains('parantha') ||
      lower.contains('bread')) {
    return 'https://images.unsplash.com/photo-1619535860434-ba1d8f4f0c03?auto=format&fit=crop&w=900&q=80';
  }
  if (lower.contains('ice cream') || lower.contains('gulab jamun')) {
    return 'https://images.unsplash.com/photo-1563805042-7684c019e1cb?auto=format&fit=crop&w=900&q=80';
  }
  if (lower.contains('lassi') ||
      lower.contains('coffee') ||
      lower.contains('milkshake') ||
      lower.contains('jaljeera') ||
      lower.contains('mojito') ||
      lower.contains('water')) {
    return 'https://images.unsplash.com/photo-1544145945-f90425340c7e?auto=format&fit=crop&w=900&q=80';
  }
  return 'https://images.unsplash.com/photo-1512058564366-18510be2db19?auto=format&fit=crop&w=900&q=80';
}

final ValueNotifier<List<BookedOrder>> kBookedOrders =
    ValueNotifier<List<BookedOrder>>(<BookedOrder>[]);
final ValueNotifier<List<BookMenuSection>> kBookMenuSections =
    ValueNotifier<List<BookMenuSection>>(
      List<BookMenuSection>.from(kDefaultBookOrderSections),
    );
final ValueNotifier<List<BillDeskAlert>> kBillDeskAlerts =
    ValueNotifier<List<BillDeskAlert>>(<BillDeskAlert>[]);
final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
final ImagePicker _imagePicker = ImagePicker();
StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
_cloudMenuSubscription;
StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
_cloudBillDeskAlertsSubscription;
final Set<String> _seenCloudBillAlertIds = <String>{};
bool _cloudInitialized = false;
bool _cloudInitAttempted = false;
int _nextBookedOrderId = 1;
int _nextBillDeskAlertId = 1;
String? _deviceId;
bool kBillMakerRemembered = false;
int _billMakerFailedAttempts = 0;
DateTime? _billMakerLockedUntil;

Future<void> _initLocalNotifications() async {
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
    macOS: DarwinInitializationSettings(),
  );
  await _localNotificationsPlugin.initialize(settings);
  try {
    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  } catch (_) {
    // Ignore permission API failures on unsupported versions/devices.
  }
}

Future<String> _ensureDeviceId() async {
  if (_deviceId != null) return _deviceId!;
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(kDeviceIdDbKey);
  if (existing != null && existing.isNotEmpty) {
    _deviceId = existing;
    return existing;
  }
  final generated = 'device_${DateTime.now().millisecondsSinceEpoch}';
  await prefs.setString(kDeviceIdDbKey, generated);
  _deviceId = generated;
  return generated;
}

Future<bool> _ensureCloudInitialized() async {
  if (_cloudInitAttempted) return _cloudInitialized;
  _cloudInitAttempted = true;
  try {
    await Firebase.initializeApp();
    _cloudInitialized = true;
  } catch (_) {
    _cloudInitialized = false;
  }
  return _cloudInitialized;
}

Future<void> _startCloudMenuSync() async {
  if (!await _ensureCloudInitialized()) return;

  _cloudMenuSubscription?.cancel();
  _cloudMenuSubscription = FirebaseFirestore.instance
      .collection(kCloudSyncCollection)
      .doc(kCloudMenuDocument)
      .snapshots()
      .listen((snapshot) async {
        final data = snapshot.data();
        final sectionsRaw = data?['sections'] as List<dynamic>?;
        if (sectionsRaw == null) return;
        final cloudSections = sectionsRaw
            .map(
              (item) => BookMenuSection.fromJson(item as Map<String, dynamic>),
            )
            .toList();
        if (cloudSections.isEmpty) return;
        final localRaw = jsonEncode(
          kBookMenuSections.value.map((e) => e.toJson()).toList(),
        );
        final cloudRaw = jsonEncode(
          cloudSections.map((e) => e.toJson()).toList(),
        );
        if (localRaw == cloudRaw) return;
        kBookMenuSections.value = cloudSections;
        await _persistBookMenuSections();
      });
}

Future<void> _pushMenuSectionsToCloud(List<BookMenuSection> sections) async {
  if (!await _ensureCloudInitialized()) return;
  final payload = sections.map((e) => e.toJson()).toList();
  try {
    await FirebaseFirestore.instance
        .collection(kCloudSyncCollection)
        .doc(kCloudMenuDocument)
        .set({'sections': payload, 'updatedAt': FieldValue.serverTimestamp()});
  } catch (_) {
    // Ignore cloud write errors; local persistence is already done.
  }
}

Future<String?> _pickImageDataUri(ImageSource source) async {
  try {
    final file = await _imagePicker.pickImage(
      source: source,
      imageQuality: 65,
      maxWidth: 900,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return 'data:image/jpeg;base64,${base64Encode(bytes)}';
  } catch (_) {
    return null;
  }
}

Future<void> _hydrateBookMenuSections() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kBookMenuDbKey);
    if (raw == null || raw.isEmpty) {
      kBookMenuSections.value = List<BookMenuSection>.from(
        kDefaultBookOrderSections,
      );
      return;
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    final restored = decoded
        .map((e) => BookMenuSection.fromJson(e as Map<String, dynamic>))
        .toList();
    if (restored.isNotEmpty) {
      kBookMenuSections.value = restored;
    }
  } catch (_) {
    kBookMenuSections.value = List<BookMenuSection>.from(
      kDefaultBookOrderSections,
    );
  }
  unawaited(_loadCloudMenuOnce());
}

Future<void> _persistBookMenuSections() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(
      kBookMenuSections.value.map((e) => e.toJson()).toList(),
    );
    await prefs.setString(kBookMenuDbKey, raw);
  } catch (_) {
    // Ignore persistence failures.
  }
}

Future<void> _loadCloudMenuOnce() async {
  if (!await _ensureCloudInitialized()) return;
  try {
    final snapshot = await FirebaseFirestore.instance
        .collection(kCloudSyncCollection)
        .doc(kCloudMenuDocument)
        .get();
    final data = snapshot.data();
    final sectionsRaw = data?['sections'] as List<dynamic>?;
    if (sectionsRaw == null || sectionsRaw.isEmpty) {
      await _pushMenuSectionsToCloud(kBookMenuSections.value);
      return;
    }
    final cloudSections = sectionsRaw
        .map((item) => BookMenuSection.fromJson(item as Map<String, dynamic>))
        .toList();
    if (cloudSections.isEmpty) return;
    kBookMenuSections.value = cloudSections;
    await _persistBookMenuSections();
  } catch (_) {
    // Ignore cloud read errors and keep local data.
  }
}

String _bookMenuImageForItem(BookMenuItem item) {
  final custom = item.imageUrl?.trim() ?? '';
  if (custom.isNotEmpty) return custom;
  return _bookMenuImageFor(item.name);
}

Future<void> _hydrateBookedOrders() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kBookedOrdersDbKey);
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw) as List<dynamic>;
    final restored = decoded
        .map((e) => BookedOrder.fromJson(e as Map<String, dynamic>))
        .toList();
    kBookedOrders.value = restored;
    _nextBookedOrderId = restored.fold<int>(
      1,
      (current, order) => order.id >= current ? order.id + 1 : current,
    );
  } catch (_) {
    // Ignore malformed cache and keep app running.
  }
}

Future<void> _persistBookedOrders() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(kBookedOrders.value.map((e) => e.toJson()).toList());
    await prefs.setString(kBookedOrdersDbKey, raw);
  } catch (_) {
    // Ignore persistence failures.
  }
}

Future<void> _hydrateBillDeskAlerts() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kBillDeskAlertsDbKey);
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw) as List<dynamic>;
    final restored = decoded
        .map((e) => BillDeskAlert.fromJson(e as Map<String, dynamic>))
        .toList();
    kBillDeskAlerts.value = restored;
    _nextBillDeskAlertId = restored.fold<int>(
      1,
      (current, alert) => alert.id >= current ? alert.id + 1 : current,
    );
  } catch (_) {
    // Ignore malformed cache.
  }
}

Future<void> _persistBillDeskAlerts() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(
      kBillDeskAlerts.value.map((e) => e.toJson()).toList(),
    );
    await prefs.setString(kBillDeskAlertsDbKey, raw);
  } catch (_) {
    // Ignore persistence failures.
  }
}

Future<void> _showBillDeskLocalNotification(BillDeskAlert alert) async {
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'bill_desk_orders_channel',
      'Bill Desk Orders',
      channelDescription: 'Notifications for new restaurant orders',
      importance: Importance.max,
      priority: Priority.high,
    ),
  );
  await _localNotificationsPlugin.show(
    alert.id,
    alert.title,
    alert.message,
    details,
  );
}

Future<void> _pushBillDeskAlert({
  required BillDeskAlertSource source,
  required String customerName,
  required String phone,
  required int itemCount,
  required int totalAmount,
  required String paymentLabel,
  int? linkedBookedOrderId,
}) async {
  final now = DateTime.now();
  final localAlert = BillDeskAlert(
    id: _nextBillDeskAlertId++,
    title: source == BillDeskAlertSource.hotelDesk
        ? 'New Hotel Booking Order'
        : 'New Online Delivery Order',
    message:
        '$customerName • $itemCount items • INR $totalAmount • $paymentLabel',
    source: source,
    customerName: customerName,
    phone: phone,
    totalAmount: totalAmount,
    itemCount: itemCount,
    createdAt: now,
    linkedBookedOrderId: linkedBookedOrderId,
    resolved: false,
  );

  final copied = List<BillDeskAlert>.from(kBillDeskAlerts.value);
  copied.insert(0, localAlert);
  kBillDeskAlerts.value = copied;
  await _persistBillDeskAlerts();
  await _showBillDeskLocalNotification(localAlert);
  await _pushBillDeskAlertToCloud(localAlert);
}

Future<void> _resolveBillDeskAlertsForBookedOrder(int bookedOrderId) async {
  final remaining = <BillDeskAlert>[];
  final removed = <BillDeskAlert>[];
  for (final alert in kBillDeskAlerts.value) {
    if (alert.linkedBookedOrderId == bookedOrderId && !alert.resolved) {
      removed.add(alert);
    } else {
      remaining.add(alert);
    }
  }
  if (removed.isEmpty) return;
  kBillDeskAlerts.value = remaining;
  await _persistBillDeskAlerts();
  for (final alert in removed) {
    await _localNotificationsPlugin.cancel(alert.id);
  }
  if (!await _ensureCloudInitialized()) return;
  for (final alert in removed) {
    if (alert.cloudId == null || alert.cloudId!.isEmpty) continue;
    try {
      await FirebaseFirestore.instance
          .collection(kCloudBillDeskAlertsCollection)
          .doc(alert.cloudId)
          .update({'resolved': true});
    } catch (_) {
      // Ignore cloud sync failures.
    }
  }
}

Future<void> _pushBillDeskAlertToCloud(BillDeskAlert alert) async {
  if (!await _ensureCloudInitialized()) return;
  final deviceId = await _ensureDeviceId();
  try {
    await FirebaseFirestore.instance
        .collection(kCloudBillDeskAlertsCollection)
        .add({
          'title': alert.title,
          'message': alert.message,
          'source': alert.source.name,
          'customerName': alert.customerName,
          'phone': alert.phone,
          'totalAmount': alert.totalAmount,
          'itemCount': alert.itemCount,
          'createdAt': alert.createdAt.toIso8601String(),
          'originDeviceId': deviceId,
          'linkedBookedOrderId': alert.linkedBookedOrderId,
          'resolved': false,
        });
  } catch (_) {
    // Ignore cloud write failures.
  }
}

Future<void> _startCloudBillDeskAlertsSync() async {
  if (!await _ensureCloudInitialized()) return;
  await _ensureDeviceId();
  _cloudBillDeskAlertsSubscription?.cancel();
  _cloudBillDeskAlertsSubscription = FirebaseFirestore.instance
      .collection(kCloudBillDeskAlertsCollection)
      .snapshots()
      .listen((snapshot) async {
        final currentDeviceId = _deviceId;
        final cloudAlerts = snapshot.docs
            .map((doc) => BillDeskAlert.fromCloud(doc.id, doc.data()))
            .where((alert) => !alert.resolved)
            .toList();
        cloudAlerts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        final localByCloudId = <String>{};
        for (final alert in kBillDeskAlerts.value) {
          if (alert.cloudId != null && alert.cloudId!.isNotEmpty) {
            localByCloudId.add(alert.cloudId!);
          }
        }

        var localUpdated = false;
        final copied = List<BillDeskAlert>.from(kBillDeskAlerts.value);
        for (final cloudAlert in cloudAlerts) {
          final cloudId = cloudAlert.cloudId;
          if (cloudId == null || localByCloudId.contains(cloudId)) continue;
          final merged = cloudAlert.copyWith(id: _nextBillDeskAlertId++);
          copied.insert(0, merged);
          localByCloudId.add(cloudId);
          localUpdated = true;

          final fromOtherDevice =
              currentDeviceId != null &&
              cloudAlert.originDeviceId != null &&
              cloudAlert.originDeviceId != currentDeviceId;
          if (fromOtherDevice && !_seenCloudBillAlertIds.contains(cloudId)) {
            _seenCloudBillAlertIds.add(cloudId);
            await _showBillDeskLocalNotification(merged);
          }
        }
        if (!localUpdated) return;
        kBillDeskAlerts.value = copied;
        await _persistBillDeskAlerts();
      });
}

int _pushBookedOrder({
  required String customerName,
  required String phone,
  required List<BookedOrderItem> items,
  required int totalAmount,
}) {
  final orderId = _nextBookedOrderId++;
  final copied = List<BookedOrder>.from(kBookedOrders.value);
  copied.insert(
    0,
    BookedOrder(
      id: orderId,
      customerName: customerName,
      phone: phone,
      items: items,
      totalAmount: totalAmount,
      createdAt: DateTime.now(),
    ),
  );
  kBookedOrders.value = copied;
  _persistBookedOrders();
  return orderId;
}

void _confirmBookedOrder(int id) {
  final updated = kBookedOrders.value
      .map(
        (order) => order.id == id
            ? order.copyWith(status: BookedOrderStatus.completed)
            : order,
      )
      .toList();
  kBookedOrders.value = updated;
  _persistBookedOrders();
  unawaited(_resolveBillDeskAlertsForBookedOrder(id));
}

void _cancelBookedOrder(int id) {
  final updated = kBookedOrders.value
      .map(
        (order) => order.id == id
            ? order.copyWith(status: BookedOrderStatus.cancelled)
            : order,
      )
      .toList();
  kBookedOrders.value = updated;
  _persistBookedOrders();
  unawaited(_resolveBillDeskAlertsForBookedOrder(id));
}

bool _isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

bool _isSameMonth(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month;
}

String _normalizePhone(String value) {
  return value.replaceAll(RegExp(r'[^0-9]'), '');
}

bool _isValidIndianPhone(String value) {
  final normalized = _normalizePhone(value);
  return normalized.length == 10;
}

Duration? _billMakerRemainingLockDuration() {
  final lockedUntil = _billMakerLockedUntil;
  if (lockedUntil == null) return null;
  final now = DateTime.now();
  if (!now.isBefore(lockedUntil)) {
    _billMakerLockedUntil = null;
    return null;
  }
  return lockedUntil.difference(now);
}

void _registerBillMakerFailure() {
  _billMakerFailedAttempts += 1;
  if (_billMakerFailedAttempts >= kBillMakerMaxLoginAttempts) {
    _billMakerLockedUntil = DateTime.now().add(kBillMakerLockoutDuration);
    _billMakerFailedAttempts = 0;
  }
}

void _resetBillMakerLoginFailures() {
  _billMakerFailedAttempts = 0;
  _billMakerLockedUntil = null;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Restaurant',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE65100),
          primary: const Color(0xFFE65100),
          secondary: const Color(0xFFFFB300),
          surface: const Color(0xFFFFF8F0),
        ),
        scaffoldBackgroundColor: const Color(0xFFFFF8F0),
      ),
      home: const RestaurantHomePage(),
    );
  }
}

class RestaurantHomePage extends StatelessWidget {
  const RestaurantHomePage({super.key});

  static const List<_StaffMember> _staffMembers = [
    _StaffMember(name: 'Ravi Kumar', role: 'Head Chef'),
    _StaffMember(name: 'Neha Singh', role: 'Service Lead'),
    _StaffMember(name: 'Amit Yadav', role: 'Floor Supervisor'),
    _StaffMember(name: 'Pooja Verma', role: 'Billing Executive'),
  ];

  static const _ManagerInfo _manager = _ManagerInfo(
    name: 'Mr. Arjun Malhotra',
    title: 'Restaurant Manager',
    email: 'manager.motimahal@example.com',
  );

  void _showStaffSection(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hotel Staff',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                for (final member in _staffMembers)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFFF3E0),
                        child: Icon(
                          Icons.person_outline_rounded,
                          color: Color(0xFFE65100),
                        ),
                      ),
                      title: Text(member.name),
                      subtitle: Text(member.role),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showManagerSection(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Manager Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _manager.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(_manager.title),
              const SizedBox(height: 8),
              Text('Email: ${_manager.email}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _shareApp(BuildContext context) {
    Share.share(
      'Try Restaurant app for online order and table booking.\nDownload now: https://motimahal.example/app',
      subject: 'Restaurant App',
    );
  }

  Future<void> _showOrderHistorySection(BuildContext context) async {
    final phoneController = TextEditingController();
    final selectedPhone = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('View Your Orders'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter your phone number to see only your order history.',
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final normalized = _normalizePhone(phoneController.text.trim());
                if (normalized.length < 10) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Enter a valid phone number.'),
                    ),
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(normalized);
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
    if (selectedPhone == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.8,
            child: ValueListenableBuilder<List<BookedOrder>>(
              valueListenable: kBookedOrders,
              builder: (context, orders, __) {
                final userOrders = orders
                    .where(
                      (order) => _normalizePhone(order.phone) == selectedPhone,
                    )
                    .toList();
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Order History',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Orders for +91 $selectedPhone: ${userOrders.length}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: userOrders.isEmpty
                            ? const Center(
                                child: Text(
                                  'No previous orders found for this number.',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              )
                            : ListView.separated(
                                itemCount: userOrders.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (_, index) {
                                  final order = userOrders[index];
                                  final statusColor = switch (order.status) {
                                    BookedOrderStatus.pending => const Color(
                                      0xFFE65100,
                                    ),
                                    BookedOrderStatus.completed => const Color(
                                      0xFF2E7D32,
                                    ),
                                    BookedOrderStatus.cancelled => const Color(
                                      0xFFC62828,
                                    ),
                                  };
                                  final statusText = switch (order.status) {
                                    BookedOrderStatus.pending => 'Pending',
                                    BookedOrderStatus.completed => 'Completed',
                                    BookedOrderStatus.cancelled => 'Cancelled',
                                  };
                                  return Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Order #${order.id} - ${order.customerName}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                statusText,
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text('Phone: ${order.phone}'),
                                          Text(
                                            'Date: ${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year}',
                                            style: const TextStyle(
                                              color: Colors.black54,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          _OrderItemsPanel(
                                            title: 'Ordered Items',
                                            items: order.items,
                                            totalAmount: order.totalAmount,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showBillDeskAlertsSection(BuildContext context) {
    BillDeskAlertSourceFilter sourceFilter = BillDeskAlertSourceFilter.all;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.82,
            child: StatefulBuilder(
              builder: (context, setModalState) {
                return ValueListenableBuilder<List<BillDeskAlert>>(
                  valueListenable: kBillDeskAlerts,
                  builder: (context, alerts, __) {
                    final activeAlerts = alerts
                        .where((alert) => !alert.resolved)
                        .toList();
                    final filtered = activeAlerts.where((alert) {
                      return switch (sourceFilter) {
                        BillDeskAlertSourceFilter.all => true,
                        BillDeskAlertSourceFilter.hotelDesk =>
                          alert.source == BillDeskAlertSource.hotelDesk,
                        BillDeskAlertSourceFilter.onlineDelivery =>
                          alert.source == BillDeskAlertSource.onlineDelivery,
                      };
                    }).toList();
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Bill Desk Alerts',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Total alerts: ${activeAlerts.length}',
                            style: const TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _FilterChip(
                                label: 'All',
                                selected:
                                    sourceFilter ==
                                    BillDeskAlertSourceFilter.all,
                                onTap: () => setModalState(
                                  () => sourceFilter =
                                      BillDeskAlertSourceFilter.all,
                                ),
                              ),
                              _FilterChip(
                                label: 'Hotel Booking',
                                selected:
                                    sourceFilter ==
                                    BillDeskAlertSourceFilter.hotelDesk,
                                onTap: () => setModalState(
                                  () => sourceFilter =
                                      BillDeskAlertSourceFilter.hotelDesk,
                                ),
                              ),
                              _FilterChip(
                                label: 'Online Delivery',
                                selected:
                                    sourceFilter ==
                                    BillDeskAlertSourceFilter.onlineDelivery,
                                onTap: () => setModalState(
                                  () => sourceFilter =
                                      BillDeskAlertSourceFilter.onlineDelivery,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: filtered.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No alerts yet.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: filtered.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 10),
                                    itemBuilder: (_, index) {
                                      final alert = filtered[index];
                                      final isOnline =
                                          alert.source ==
                                          BillDeskAlertSource.onlineDelivery;
                                      final accent = isOnline
                                          ? const Color(0xFF1565C0)
                                          : const Color(0xFFE65100);
                                      final softBg = isOnline
                                          ? const Color(0xFFE3F2FD)
                                          : const Color(0xFFFFF3E0);
                                      return Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFFFDFC6),
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Color(0x12000000),
                                              blurRadius: 10,
                                              offset: Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 5,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: softBg,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      isOnline
                                                          ? 'Online Delivery'
                                                          : 'Hotel Booking',
                                                      style: TextStyle(
                                                        color: accent,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    '${alert.createdAt.hour.toString().padLeft(2, '0')}:${alert.createdAt.minute.toString().padLeft(2, '0')}',
                                                    style: const TextStyle(
                                                      color: Colors.black54,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                alert.title,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                alert.message,
                                                style: const TextStyle(
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  _AlertInfoChip(
                                                    icon: Icons
                                                        .person_outline_rounded,
                                                    text: alert.customerName,
                                                  ),
                                                  _AlertInfoChip(
                                                    icon: Icons.call_outlined,
                                                    text: alert.phone,
                                                  ),
                                                  _AlertInfoChip(
                                                    icon:
                                                        Icons.payments_outlined,
                                                    text:
                                                        'INR ${alert.totalAmount}',
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  int _pendingCount() {
    return kBookedOrders.value
        .where((order) => order.status == BookedOrderStatus.pending)
        .length;
  }

  void _onHomeMenuAction(BuildContext context, _HomeMenuAction action) {
    switch (action) {
      case _HomeMenuAction.hotelStaff:
        _showStaffSection(context);
      case _HomeMenuAction.managerDetails:
        _showManagerSection(context);
      case _HomeMenuAction.orderHistory:
        _showOrderHistorySection(context);
      case _HomeMenuAction.billMakerLogin:
        if (kBillMakerRemembered) {
          _showBillMakerDesk(context);
        } else {
          _showBillMakerLogin(context);
        }
      case _HomeMenuAction.shareApp:
        _shareApp(context);
    }
  }

  void _showHomeMenuSheet(BuildContext context, {required bool hasPending}) {
    final parentContext = context;
    const actions = [
      (
        action: _HomeMenuAction.hotelStaff,
        title: 'Hotel Staff',
        icon: Icons.people_outline_rounded,
      ),
      (
        action: _HomeMenuAction.managerDetails,
        title: 'Manager Details',
        icon: Icons.badge_outlined,
      ),
      (
        action: _HomeMenuAction.orderHistory,
        title: 'Order History',
        icon: Icons.history_rounded,
      ),
      (
        action: _HomeMenuAction.billMakerLogin,
        title: 'Bill Maker Login',
        icon: Icons.receipt_long_rounded,
      ),
      (
        action: _HomeMenuAction.shareApp,
        title: 'Share App',
        icon: Icons.share_outlined,
      ),
    ];
    Future<void> triggerAction(_HomeMenuAction action) async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!parentContext.mounted) return;
      _onHomeMenuAction(parentContext, action);
    }

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Quick Menu',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    if (hasPending)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Pending Orders',
                          style: TextStyle(
                            color: Color(0xFFC62828),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 500;
                    if (compact) {
                      return Column(
                        children: [
                          for (final menuItem in actions)
                            _QuickMenuActionTile(
                              title: menuItem.title,
                              icon: menuItem.icon,
                              onTap: () async {
                                Navigator.of(context).pop();
                                await triggerAction(menuItem.action);
                              },
                            ),
                        ],
                      );
                    }
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final menuItem in actions)
                          SizedBox(
                            width: (constraints.maxWidth - 10) / 2,
                            child: _QuickMenuActionTile(
                              title: menuItem.title,
                              icon: menuItem.icon,
                              onTap: () async {
                                Navigator.of(context).pop();
                                await triggerAction(menuItem.action);
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showBillMakerLogin(BuildContext context) {
    final userController = TextEditingController();
    final passController = TextEditingController();
    var rememberMe = kBillMakerRemembered;
    var showPassword = false;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              backgroundColor: const Color(0xFFFFFAF5),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE65100), Color(0xFFF57C00)],
                            ),
                          ),
                          child: Row(
                            children: const [
                              CircleAvatar(
                                backgroundColor: Color(0x33FFFFFF),
                                child: Icon(
                                  Icons.storefront_rounded,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Restaurant',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Hotel Bill Maker Login',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Use registered mobile and password.',
                          style: TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: userController,
                          keyboardType: TextInputType.phone,
                          obscureText: false,
                          enableSuggestions: false,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Mobile Number',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: passController,
                          obscureText: !showPassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setLocalState(() {
                                  showPassword = !showPassword;
                                });
                              },
                              icon: Icon(
                                showPassword
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: rememberMe,
                          title: const Text('Remember me'),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (value) {
                            setLocalState(() {
                              rememberMe = value ?? false;
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                        if (_billMakerRemainingLockDuration() != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Too many failed attempts. Please wait ${_billMakerRemainingLockDuration()!.inSeconds}s.',
                              style: const TextStyle(
                                color: Color(0xFFC62828),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () async {
                                final lockRemaining =
                                    _billMakerRemainingLockDuration();
                                if (lockRemaining != null) {
                                  setLocalState(() {});
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Login is temporarily locked. Try again in ${lockRemaining.inSeconds}s.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                final user = _normalizePhone(
                                  userController.text.trim(),
                                );
                                final pass = passController.text.trim();
                                if (!_isValidIndianPhone(userController.text)) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Enter a valid 10-digit mobile number.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                if (user == _normalizePhone(kBillMakerUser) &&
                                    pass == kBillMakerPass) {
                                  _resetBillMakerLoginFailures();
                                  kBillMakerRemembered = rememberMe;
                                  Navigator.of(dialogContext).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: const Color(0xFF2E7D32),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      content: const Row(
                                        children: [
                                          Icon(
                                            Icons.verified_user_rounded,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'You are logged in successfully.',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  await Future<void>.delayed(
                                    const Duration(milliseconds: 160),
                                  );
                                  if (!context.mounted) return;
                                  _showBillMakerDesk(context);
                                } else {
                                  _registerBillMakerFailure();
                                  setLocalState(() {});
                                  final remainingLock =
                                      _billMakerRemainingLockDuration();
                                  if (remainingLock != null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Too many failed attempts. Locked for ${remainingLock.inSeconds}s.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  final remainingAttempts =
                                      kBillMakerMaxLoginAttempts -
                                      _billMakerFailedAttempts;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Invalid login credentials. Attempts left: $remainingAttempts',
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: const Text('Login'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showBillMakerDesk(BuildContext context) async {
    _hydrateBookMenuSections();
    final selectedPortal = await showModalBottomSheet<_BillMakerPortal>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bill Maker Desk',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Select a portal to continue.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop(_BillMakerPortal.orders);
                    },
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text('Orders Portal'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pop(_BillMakerPortal.menuManagement);
                    },
                    icon: const Icon(Icons.restaurant_menu_rounded),
                    label: const Text('Menu Management Portal'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop(_BillMakerPortal.alerts);
                    },
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Bill Desk Alerts'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!context.mounted || selectedPortal == null) return;
    switch (selectedPortal) {
      case _BillMakerPortal.orders:
        _showBillOrdersPortal(context);
      case _BillMakerPortal.menuManagement:
        _showMenuManagementPortal(context);
      case _BillMakerPortal.alerts:
        _showBillDeskAlertsSection(context);
    }
  }

  void _showMenuManagementPortal(BuildContext context) {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final imageController = TextEditingController();
    final searchController = TextEditingController();
    final editNameController = TextEditingController();
    final editPriceController = TextEditingController();
    final editImageController = TextEditingController();
    String? selectedSectionTitle;
    String? editingItemKey;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.88,
            child: StatefulBuilder(
              builder: (context, setModalState) {
                return ValueListenableBuilder<List<BookMenuSection>>(
                  valueListenable: kBookMenuSections,
                  builder: (context, sections, __) {
                    final searchQuery = searchController.text
                        .trim()
                        .toLowerCase();
                    final totalItems = sections.fold<int>(
                      0,
                      (total, section) => total + section.items.length,
                    );
                    final visibleItems = sections.fold<int>(
                      0,
                      (total, section) =>
                          total +
                          section.items
                              .where(
                                (item) =>
                                    searchQuery.isEmpty ||
                                    item.name.toLowerCase().contains(
                                      searchQuery,
                                    ) ||
                                    section.title.toLowerCase().contains(
                                      searchQuery,
                                    ),
                              )
                              .length,
                    );
                    if (sections.isNotEmpty &&
                        (selectedSectionTitle == null ||
                            !sections.any(
                              (section) =>
                                  section.title == selectedSectionTitle,
                            ))) {
                      selectedSectionTitle = sections.first.title;
                    }

                    Future<void> saveSections(
                      List<BookMenuSection> nextSections,
                    ) async {
                      kBookMenuSections.value = nextSections;
                      await _persistBookMenuSections();
                      await _pushMenuSectionsToCloud(nextSections);
                    }

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                      child: ListView(
                        children: [
                          const Text(
                            'Menu Management Portal',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            searchQuery.isEmpty
                                ? 'Total food items: $totalItems'
                                : 'Total food items: $totalItems • Showing: $visibleItems',
                            style: const TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: searchController,
                            onChanged: (_) => setModalState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Search for Edit/Delete',
                              hintText: 'Search by item or section',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: searchController.text.trim().isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed: () {
                                        searchController.clear();
                                        setModalState(() {});
                                      },
                                      icon: const Icon(Icons.clear_rounded),
                                    ),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Card(
                            color: Colors.white,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                children: [
                                  DropdownButtonFormField<String>(
                                    initialValue: selectedSectionTitle,
                                    decoration: const InputDecoration(
                                      labelText: 'Section',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: sections
                                        .map(
                                          (section) => DropdownMenuItem<String>(
                                            value: section.title,
                                            child: Text(section.title),
                                          ),
                                        )
                                        .toList(growable: false),
                                    onChanged: (value) {
                                      setModalState(
                                        () => selectedSectionTitle = value,
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: nameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Food Item Name',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: priceController,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Price (INR)',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: imageController,
                                    decoration: const InputDecoration(
                                      labelText: 'Image URL (optional)',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFFBF8),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFFFDFC6),
                                      ),
                                    ),
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final compact =
                                            constraints.maxWidth < 360;
                                        if (compact) {
                                          return Column(
                                            children: [
                                              SizedBox(
                                                width: double.infinity,
                                                child: OutlinedButton.icon(
                                                  onPressed: () async {
                                                    final dataUri =
                                                        await _pickImageDataUri(
                                                          ImageSource.gallery,
                                                        );
                                                    if (dataUri == null) {
                                                      return;
                                                    }
                                                    imageController.text =
                                                        dataUri;
                                                    if (!context.mounted) {
                                                      return;
                                                    }
                                                    setModalState(() {});
                                                  },
                                                  icon: const Icon(
                                                    Icons
                                                        .photo_library_outlined,
                                                  ),
                                                  label: const Text(
                                                    'Choose from Gallery',
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              SizedBox(
                                                width: double.infinity,
                                                child: OutlinedButton.icon(
                                                  onPressed: () async {
                                                    final dataUri =
                                                        await _pickImageDataUri(
                                                          ImageSource.camera,
                                                        );
                                                    if (dataUri == null) {
                                                      return;
                                                    }
                                                    imageController.text =
                                                        dataUri;
                                                    if (!context.mounted) {
                                                      return;
                                                    }
                                                    setModalState(() {});
                                                  },
                                                  icon: const Icon(
                                                    Icons.photo_camera_outlined,
                                                  ),
                                                  label: const Text(
                                                    'Use Camera',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        }
                                        return Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () async {
                                                  final dataUri =
                                                      await _pickImageDataUri(
                                                        ImageSource.gallery,
                                                      );
                                                  if (dataUri == null) return;
                                                  imageController.text =
                                                      dataUri;
                                                  if (!context.mounted) {
                                                    return;
                                                  }
                                                  setModalState(() {});
                                                },
                                                icon: const Icon(
                                                  Icons.photo_library_outlined,
                                                ),
                                                label: const Text('Gallery'),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () async {
                                                  final dataUri =
                                                      await _pickImageDataUri(
                                                        ImageSource.camera,
                                                      );
                                                  if (dataUri == null) return;
                                                  imageController.text =
                                                      dataUri;
                                                  if (!context.mounted) {
                                                    return;
                                                  }
                                                  setModalState(() {});
                                                },
                                                icon: const Icon(
                                                  Icons.photo_camera_outlined,
                                                ),
                                                label: const Text('Camera'),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                  if (imageController.text.trim().isNotEmpty)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 6),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          'Image selected',
                                          style: TextStyle(
                                            color: Color(0xFF2E7D32),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: sections.isEmpty
                                          ? null
                                          : () async {
                                              final itemName = nameController
                                                  .text
                                                  .trim();
                                              final priceText = priceController
                                                  .text
                                                  .trim();
                                              final imageUrl = imageController
                                                  .text
                                                  .trim();
                                              final price = int.tryParse(
                                                priceText,
                                              );
                                              if (itemName.isEmpty) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Enter food item name.',
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              if (price == null) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Enter a valid numeric price.',
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              final sectionIndex = sections
                                                  .indexWhere(
                                                    (section) =>
                                                        section.title ==
                                                        selectedSectionTitle,
                                                  );
                                              if (sectionIndex < 0) return;

                                              final currentSection =
                                                  sections[sectionIndex];
                                              final updatedItems =
                                                  List<BookMenuItem>.from(
                                                    currentSection.items,
                                                  )..add(
                                                    BookMenuItem(
                                                      name: itemName,
                                                      price: price,
                                                      imageUrl: imageUrl.isEmpty
                                                          ? null
                                                          : imageUrl,
                                                    ),
                                                  );
                                              final updatedSections =
                                                  List<BookMenuSection>.from(
                                                    sections,
                                                  );
                                              updatedSections[sectionIndex] =
                                                  currentSection.copyWith(
                                                    items: updatedItems,
                                                  );
                                              await saveSections(
                                                updatedSections,
                                              );
                                              nameController.clear();
                                              priceController.clear();
                                              imageController.clear();
                                            },
                                      child: const Text('Add Food Item'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: sections.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, sectionIndex) {
                              final section = sections[sectionIndex];
                              final sectionVisibleItems = section.items
                                  .where(
                                    (item) =>
                                        searchQuery.isEmpty ||
                                        item.name.toLowerCase().contains(
                                          searchQuery,
                                        ) ||
                                        section.title.toLowerCase().contains(
                                          searchQuery,
                                        ),
                                  )
                                  .toList(growable: false);
                              if (searchQuery.isNotEmpty &&
                                  sectionVisibleItems.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        section.title,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      if (section.items.isEmpty)
                                        const Text(
                                          'No items in this section.',
                                          style: TextStyle(
                                            color: Colors.black54,
                                          ),
                                        )
                                      else
                                        for (final visibleItem
                                            in sectionVisibleItems)
                                          Builder(
                                            builder: (_) {
                                              final currentItemIndex = section
                                                  .items
                                                  .indexOf(visibleItem);
                                              if (currentItemIndex < 0) {
                                                return const SizedBox.shrink();
                                              }
                                              final existing = section
                                                  .items[currentItemIndex];
                                              final itemKey =
                                                  '${section.title}::$currentItemIndex';
                                              final isEditing =
                                                  editingItemKey == itemKey;
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  _MenuManageItemTile(
                                                    item: existing,
                                                    onEdit: () {
                                                      setModalState(() {
                                                        editingItemKey =
                                                            itemKey;
                                                        editNameController
                                                                .text =
                                                            existing.name;
                                                        editPriceController
                                                                .text =
                                                            (existing.price ??
                                                                    0)
                                                                .toString();
                                                        editImageController
                                                                .text =
                                                            existing.imageUrl ??
                                                            '';
                                                      });
                                                    },
                                                    onDelete: () async {
                                                      final updatedItems =
                                                          List<
                                                            BookMenuItem
                                                          >.from(section.items);
                                                      if (currentItemIndex >=
                                                          updatedItems.length) {
                                                        return;
                                                      }
                                                      updatedItems.removeAt(
                                                        currentItemIndex,
                                                      );
                                                      final updatedSections =
                                                          List<
                                                            BookMenuSection
                                                          >.from(sections);
                                                      updatedSections[sectionIndex] =
                                                          section.copyWith(
                                                            items: updatedItems,
                                                          );
                                                      await saveSections(
                                                        updatedSections,
                                                      );
                                                      if (!context.mounted) {
                                                        return;
                                                      }
                                                      if (editingItemKey ==
                                                          itemKey) {
                                                        setModalState(() {
                                                          editingItemKey = null;
                                                        });
                                                      }
                                                    },
                                                  ),
                                                  if (isEditing)
                                                    Container(
                                                      margin:
                                                          const EdgeInsets.only(
                                                            bottom: 8,
                                                          ),
                                                      padding:
                                                          const EdgeInsets.all(
                                                            10,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(
                                                          0xFFFFFBF8,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10,
                                                            ),
                                                        border: Border.all(
                                                          color: const Color(
                                                            0xFFFFDFC6,
                                                          ),
                                                        ),
                                                      ),
                                                      child: Column(
                                                        children: [
                                                          TextField(
                                                            controller:
                                                                editNameController,
                                                            decoration:
                                                                const InputDecoration(
                                                                  labelText:
                                                                      'Edit Name',
                                                                  border:
                                                                      OutlineInputBorder(),
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            height: 8,
                                                          ),
                                                          TextField(
                                                            controller:
                                                                editPriceController,
                                                            keyboardType:
                                                                TextInputType
                                                                    .number,
                                                            decoration: const InputDecoration(
                                                              labelText:
                                                                  'Edit Price (INR)',
                                                              border:
                                                                  OutlineInputBorder(),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 8,
                                                          ),
                                                          TextField(
                                                            controller:
                                                                editImageController,
                                                            decoration: const InputDecoration(
                                                              labelText:
                                                                  'Edit Image URL (optional)',
                                                              border:
                                                                  OutlineInputBorder(),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 8,
                                                          ),
                                                          Row(
                                                            mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .end,
                                                            children: [
                                                              TextButton(
                                                                onPressed: () {
                                                                  setModalState(
                                                                    () {
                                                                      editingItemKey =
                                                                          null;
                                                                    },
                                                                  );
                                                                },
                                                                child:
                                                                    const Text(
                                                                      'Cancel',
                                                                    ),
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              FilledButton(
                                                                onPressed: () async {
                                                                  final newName =
                                                                      editNameController
                                                                          .text
                                                                          .trim();
                                                                  final newPrice =
                                                                      int.tryParse(
                                                                        editPriceController
                                                                            .text
                                                                            .trim(),
                                                                      );
                                                                  final newImage =
                                                                      editImageController
                                                                          .text
                                                                          .trim();
                                                                  if (newName
                                                                          .isEmpty ||
                                                                      newPrice ==
                                                                          null) {
                                                                    ScaffoldMessenger.of(
                                                                      context,
                                                                    ).showSnackBar(
                                                                      const SnackBar(
                                                                        content:
                                                                            Text(
                                                                              'Enter valid name and numeric price.',
                                                                            ),
                                                                      ),
                                                                    );
                                                                    return;
                                                                  }
                                                                  final updatedItems =
                                                                      List<
                                                                        BookMenuItem
                                                                      >.from(
                                                                        section
                                                                            .items,
                                                                      );
                                                                  if (currentItemIndex >=
                                                                      updatedItems
                                                                          .length) {
                                                                    return;
                                                                  }
                                                                  updatedItems[currentItemIndex] = BookMenuItem(
                                                                    name:
                                                                        newName,
                                                                    price:
                                                                        newPrice,
                                                                    imageUrl:
                                                                        newImage
                                                                            .isEmpty
                                                                        ? null
                                                                        : newImage,
                                                                  );
                                                                  final updatedSections =
                                                                      List<
                                                                        BookMenuSection
                                                                      >.from(
                                                                        sections,
                                                                      );
                                                                  updatedSections[sectionIndex] =
                                                                      section.copyWith(
                                                                        items:
                                                                            updatedItems,
                                                                      );
                                                                  await saveSections(
                                                                    updatedSections,
                                                                  );
                                                                  if (!context
                                                                      .mounted) {
                                                                    return;
                                                                  }
                                                                  setModalState(
                                                                    () {
                                                                      editingItemKey =
                                                                          null;
                                                                    },
                                                                  );
                                                                },
                                                                child:
                                                                    const Text(
                                                                      'Save',
                                                                    ),
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                ],
                                              );
                                            },
                                          ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showBillOrdersPortal(BuildContext context) {
    var statusFilter = BillStatusFilter.pending;
    var dateFilter = BillDateFilter.today;
    DateTime? pickedDate;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.8,
            child: StatefulBuilder(
              builder: (context, setModalState) {
                return ValueListenableBuilder<List<BookedOrder>>(
                  valueListenable: kBookedOrders,
                  builder: (context, orders, __) {
                    final now = DateTime.now();
                    final filtered = orders.where((order) {
                      final statusMatch = switch (statusFilter) {
                        BillStatusFilter.all => true,
                        BillStatusFilter.pending =>
                          order.status == BookedOrderStatus.pending,
                        BillStatusFilter.completed =>
                          order.status == BookedOrderStatus.completed,
                        BillStatusFilter.cancelled =>
                          order.status == BookedOrderStatus.cancelled,
                      };
                      final dateMatch = switch (dateFilter) {
                        BillDateFilter.all => true,
                        BillDateFilter.today => _isSameDate(
                          order.createdAt,
                          now,
                        ),
                        BillDateFilter.month => _isSameMonth(
                          order.createdAt,
                          now,
                        ),
                        BillDateFilter.date =>
                          pickedDate != null &&
                              _isSameDate(order.createdAt, pickedDate!),
                      };
                      return statusMatch && dateMatch;
                    }).toList();

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Orders Portal',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Pending orders: ${orders.where((o) => o.status == BookedOrderStatus.pending).length}',
                            style: const TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _FilterChip(
                                label: 'All',
                                selected: statusFilter == BillStatusFilter.all,
                                onTap: () => setModalState(
                                  () => statusFilter = BillStatusFilter.all,
                                ),
                              ),
                              _FilterChip(
                                label: 'Pending',
                                selected:
                                    statusFilter == BillStatusFilter.pending,
                                onTap: () => setModalState(
                                  () => statusFilter = BillStatusFilter.pending,
                                ),
                              ),
                              _FilterChip(
                                label: 'Completed',
                                selected:
                                    statusFilter == BillStatusFilter.completed,
                                onTap: () => setModalState(
                                  () =>
                                      statusFilter = BillStatusFilter.completed,
                                ),
                              ),
                              _FilterChip(
                                label: 'Cancelled',
                                selected:
                                    statusFilter == BillStatusFilter.cancelled,
                                onTap: () => setModalState(
                                  () =>
                                      statusFilter = BillStatusFilter.cancelled,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _FilterChip(
                                label: 'Today',
                                selected: dateFilter == BillDateFilter.today,
                                onTap: () => setModalState(
                                  () => dateFilter = BillDateFilter.today,
                                ),
                              ),
                              _FilterChip(
                                label: 'This Month',
                                selected: dateFilter == BillDateFilter.month,
                                onTap: () => setModalState(
                                  () => dateFilter = BillDateFilter.month,
                                ),
                              ),
                              _FilterChip(
                                label: 'All Dates',
                                selected: dateFilter == BillDateFilter.all,
                                onTap: () => setModalState(
                                  () => dateFilter = BillDateFilter.all,
                                ),
                              ),
                              _FilterChip(
                                label: pickedDate == null
                                    ? 'Pick Date'
                                    : '${pickedDate!.day}/${pickedDate!.month}/${pickedDate!.year}',
                                selected: dateFilter == BillDateFilter.date,
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: pickedDate ?? now,
                                    firstDate: DateTime(2024),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setModalState(() {
                                      pickedDate = picked;
                                      dateFilter = BillDateFilter.date;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: filtered.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No orders for selected filters.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: filtered.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (_, index) {
                                      final order = filtered[index];
                                      final statusColor =
                                          switch (order.status) {
                                            BookedOrderStatus.pending =>
                                              const Color(0xFFE65100),
                                            BookedOrderStatus.completed =>
                                              const Color(0xFF2E7D32),
                                            BookedOrderStatus.cancelled =>
                                              const Color(0xFFC62828),
                                          };
                                      final statusBg = switch (order.status) {
                                        BookedOrderStatus.pending =>
                                          const Color(0xFFFFF3E0),
                                        BookedOrderStatus.completed =>
                                          const Color(0xFFE8F5E9),
                                        BookedOrderStatus.cancelled =>
                                          const Color(0xFFFFEBEE),
                                      };
                                      final statusText = switch (order.status) {
                                        BookedOrderStatus.pending => 'Pending',
                                        BookedOrderStatus.completed =>
                                          'Completed',
                                        BookedOrderStatus.cancelled =>
                                          'Cancelled',
                                      };

                                      return Card(
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      'Order #${order.id} - ${order.customerName}',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: statusBg,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      statusText,
                                                      style: TextStyle(
                                                        color: statusColor,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text('Phone: ${order.phone}'),
                                              Text(
                                                'Date: ${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year}',
                                                style: const TextStyle(
                                                  color: Colors.black54,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              _OrderItemsPanel(
                                                title: 'Order Items',
                                                items: order.items,
                                                totalAmount: order.totalAmount,
                                              ),
                                              if (order.status ==
                                                  BookedOrderStatus
                                                      .pending) ...[
                                                const SizedBox(height: 8),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.end,
                                                  children: [
                                                    OutlinedButton(
                                                      onPressed: () =>
                                                          _cancelBookedOrder(
                                                            order.id,
                                                          ),
                                                      child: const Text(
                                                        'Cancel',
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    FilledButton(
                                                      onPressed: () =>
                                                          _confirmBookedOrder(
                                                            order.id,
                                                          ),
                                                      child: const Text(
                                                        'Confirm',
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth >= 900 ? 28.0 : 16.0;
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 240,
                pinned: true,
                stretch: true,
                backgroundColor: const Color(0xFFE65100),
                actions: [
                  ValueListenableBuilder<List<BookedOrder>>(
                    valueListenable: kBookedOrders,
                    builder: (context, __, ___) {
                      final hasPending = _pendingCount() > 0;
                      return IconButton(
                        tooltip: 'Menu',
                        onPressed: () =>
                            _showHomeMenuSheet(context, hasPending: hasPending),
                        icon: _MenuHoverIcon(hasPending: hasPending),
                      );
                    },
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=1200&q=80',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFFFFE0B2),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.restaurant_menu_rounded,
                            size: 56,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black87,
                              Colors.black26,
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      const _HeroHeader(),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _PageContainer(
                  horizontalPadding: horizontalPadding,
                  child: _ActionSection(
                    onOnlineOrderTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const OnlineOrderPage(),
                        ),
                      );
                    },
                    onBookOrderTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const BookYourOrderPage(),
                        ),
                      );
                    },
                  ),
                ),
              ),
              for (final section in kHomeMenuSections)
                SliverToBoxAdapter(
                  child: _PageContainer(
                    horizontalPadding: horizontalPadding,
                    child: _SectionWidget(section: section),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 20 + MediaQuery.of(context).viewPadding.bottom,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PageContainer extends StatelessWidget {
  const _PageContainer({required this.child, required this.horizontalPadding});

  final Widget child;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            16,
            horizontalPadding,
            8,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({
    required this.onOnlineOrderTap,
    required this.onBookOrderTap,
  });

  final VoidCallback onOnlineOrderTap;
  final VoidCallback onBookOrderTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ActionTile(
            title: 'Online Order',
            subtitle: 'Fast delivery in 30 min',
            icon: Icons.delivery_dining_rounded,
            onTap: onOnlineOrderTap,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ActionTile(
            title: 'Book Your Order',
            subtitle: 'Reserve table & pre-order',
            icon: Icons.event_seat_rounded,
            onTap: onBookOrderTap,
          ),
        ),
      ],
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 700;
        final titleSize = isWide ? 34.0 : 26.0;
        final subtitleSize = isWide ? 14.0 : 12.0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 78, 16, 20),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 520 : 360),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE65100),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'AUTHENTIC INDIAN KITCHEN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Restaurant',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: titleSize,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Order your favorites, fresh and hot at your doorstep.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: subtitleSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFFFF3E0),
                child: Icon(icon, color: const Color(0xFFE65100)),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionWidget extends StatelessWidget {
  const _SectionWidget({required this.section});

  final MenuSection section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useGrid = constraints.maxWidth >= 900;
          final gridCardWidth = (constraints.maxWidth - 24) / 3;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              if (useGrid)
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final item in section.items)
                      SizedBox(
                        width: gridCardWidth,
                        child: _ItemCard(item: item),
                      ),
                  ],
                )
              else
                SizedBox(
                  height: 220,
                  child: Stack(
                    children: [
                      ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: section.items.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, index) =>
                            _ItemCard(item: section.items[index]),
                      ),
                      if (section.items.length > 1)
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: IgnorePointer(
                            child: Center(
                              child: Container(
                                width: 30,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.86),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: const Color(0xFFFFD6B8),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.chevron_right_rounded,
                                  color: Color(0xFFE65100),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.item});

  final MenuItem item;

  void _showOrderRouteChooser(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose how you want to place this order:',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      final prefilled = <String, int>{item.name: 1};
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              OnlineOrderPage(initialQuantities: prefilled),
                        ),
                      );
                    },
                    icon: const Icon(Icons.delivery_dining_rounded),
                    label: const Text('Online Order'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final prefilled = <String, int>{item.name: 1};
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              BookYourOrderPage(initialQuantities: prefilled),
                        ),
                      );
                    },
                    icon: const Icon(Icons.event_seat_rounded),
                    label: const Text('Book Your Order'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showOrderRouteChooser(context),
        child: Container(
          width: 165,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _FoodImage(imageUrl: item.imageUrl)),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'INR ${item.price}',
                        style: const TextStyle(
                          color: Color(0xFFE65100),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BookYourOrderPage extends StatefulWidget {
  const BookYourOrderPage({super.key, this.initialQuantities});

  final Map<String, int>? initialQuantities;

  @override
  State<BookYourOrderPage> createState() => _BookYourOrderPageState();
}

class _BookYourOrderPageState extends State<BookYourOrderPage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customerNameController = TextEditingController();
  final TextEditingController _customerPhoneController =
      TextEditingController();
  final Map<String, int> _quantities = <String, int>{};

  @override
  void initState() {
    super.initState();
    if (widget.initialQuantities != null) {
      _quantities.addAll(widget.initialQuantities!);
    }
  }

  String get _searchQuery => _searchController.text.trim().toLowerCase();

  bool _matchesQuery(String itemName, String sectionTitle) {
    if (_searchQuery.isEmpty) return true;
    return itemName.toLowerCase().contains(_searchQuery) ||
        sectionTitle.toLowerCase().contains(_searchQuery);
  }

  int get _subtotal {
    var total = 0;
    for (final section in kBookMenuSections.value) {
      for (final item in section.items) {
        total += (item.price ?? 0) * (_quantities[item.name] ?? 0);
      }
    }
    return total;
  }

  void _changeQty(BookMenuItem item, int delta) {
    final current = _quantities[item.name] ?? 0;
    final next = current + delta;
    setState(() {
      if (next <= 0) {
        _quantities.remove(item.name);
      } else {
        _quantities[item.name] = next;
      }
    });
  }

  List<BookedOrderItem> _selectedItems() {
    final selected = <BookedOrderItem>[];
    for (final section in kBookMenuSections.value) {
      for (final item in section.items) {
        final qty = _quantities[item.name] ?? 0;
        if (qty > 0) {
          selected.add(
            BookedOrderItem(
              name: item.name,
              quantity: qty,
              unitPrice: item.price ?? 0,
            ),
          );
        }
      }
    }
    return selected;
  }

  void _submitBookOrder() {
    final selectedItems = _selectedItems();
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one menu item.')),
      );
      return;
    }
    if (_customerNameController.text.trim().isEmpty ||
        !_isValidIndianPhone(_customerPhoneController.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid customer name and phone.')),
      );
      return;
    }

    final bookedOrderId = _pushBookedOrder(
      customerName: _customerNameController.text.trim(),
      phone: _customerPhoneController.text.trim(),
      items: selectedItems,
      totalAmount: _subtotal,
    );
    unawaited(
      _pushBillDeskAlert(
        source: BillDeskAlertSource.hotelDesk,
        customerName: _customerNameController.text.trim(),
        phone: _customerPhoneController.text.trim(),
        itemCount: selectedItems.fold<int>(
          0,
          (total, item) => total + item.quantity,
        ),
        totalAmount: _subtotal,
        paymentLabel: 'Pay at Bill Desk',
        linkedBookedOrderId: bookedOrderId,
      ),
    );

    setState(() {
      _quantities.clear();
    });
    _searchController.clear();
    _customerNameController.clear();
    _customerPhoneController.clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Order sent to Bill Maker desk.')),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafePadding = MediaQuery.of(context).viewPadding.bottom;
    return Scaffold(
      appBar: AppBar(title: const Text('Book Your Order')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth >= 900 ? 24.0 : 16.0;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              16,
              horizontalPadding,
              20 + bottomSafePadding,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _ModernListHeader(
                      title: 'Restaurant - Full Menu',
                      subtitle: 'Search and add items for booking.',
                      badgeText: 'BOOKING',
                      icon: Icons.menu_book_rounded,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search food like biryani, dessert...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final section in kBookMenuSections.value)
                      if (section.items
                          .where(
                            (item) => _matchesQuery(item.name, section.title),
                          )
                          .isNotEmpty)
                        _BookSectionWidget(
                          title: section.title,
                          items: section.items
                              .where(
                                (item) =>
                                    _matchesQuery(item.name, section.title),
                              )
                              .toList(),
                          quantities: _quantities,
                          onAdd: (item) => _changeQty(item, 1),
                          onRemove: (item) => _changeQty(item, -1),
                        ),
                    if (kBookMenuSections.value.every(
                      (section) => section.items
                          .where(
                            (item) => _matchesQuery(item.name, section.title),
                          )
                          .isEmpty,
                    ))
                      const Padding(
                        padding: EdgeInsets.only(top: 18),
                        child: Text(
                          'No matching items found.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Card(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Take Menu',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _customerNameController,
                              decoration: const InputDecoration(
                                labelText: 'Customer Name',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _customerPhoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Phone Number',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const Divider(),
                            _SummaryRow(
                              label: 'Booking Total',
                              value: _subtotal,
                              highlight: true,
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: _HoverActionButton(
                                label: 'Book Your Order Now',
                                onPressed: _submitBookOrder,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BookSectionWidget extends StatelessWidget {
  const _BookSectionWidget({
    required this.title,
    required this.items,
    required this.quantities,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final List<BookMenuItem> items;
  final Map<String, int> quantities;
  final ValueChanged<BookMenuItem> onAdd;
  final ValueChanged<BookMenuItem> onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (items.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFFFD6B8)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Slide',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE65100),
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: Color(0xFFE65100),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 305,
            child: Stack(
              children: [
                ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, index) => SizedBox(
                    width: 180,
                    child: _BookItemCard(
                      item: items[index],
                      quantity: quantities[items[index].name] ?? 0,
                      onAdd: () => onAdd(items[index]),
                      onRemove: () => onRemove(items[index]),
                    ),
                  ),
                ),
                if (items.length > 1)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 30,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.86),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFFFD6B8)),
                          ),
                          child: const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BookItemCard extends StatelessWidget {
  const _BookItemCard({
    required this.item,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final BookMenuItem item;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final displayPrice = item.price == null
        ? 'Price on request'
        : 'INR ${item.price}';
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFDFC6)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _FoodImage(imageUrl: _bookMenuImageForItem(item))),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    displayPrice,
                    style: const TextStyle(
                      color: Color(0xFFE65100),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton(
                        onPressed: onRemove,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text(
                        '$quantity',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      IconButton(
                        onPressed: onAdd,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModernListHeader extends StatelessWidget {
  const _ModernListHeader({
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String badgeText;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF1E6), Color(0xFFFFF9F3)],
        ),
        border: Border.all(color: const Color(0xFFFFDFC6)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderBadge(icon: icon, text: badgeText),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _HeaderBadge(icon: icon, text: badgeText),
            ],
          );
        },
      ),
    );
  }
}

class _HeaderBadge extends StatelessWidget {
  const _HeaderBadge({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE65100),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class OnlineOrderPage extends StatefulWidget {
  const OnlineOrderPage({super.key, this.initialQuantities});

  final Map<String, int>? initialQuantities;

  @override
  State<OnlineOrderPage> createState() => _OnlineOrderPageState();
}

class _OnlineOrderPageState extends State<OnlineOrderPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _menuSearchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _couponController = TextEditingController();

  final Map<String, int> _quantities = <String, int>{};
  PaymentMethod _paymentMethod = PaymentMethod.cashOnDelivery;
  String? _appliedCoupon;
  int _discountAmount = 0;
  bool _isPayingOnline = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuantities != null) {
      _quantities.addAll(widget.initialQuantities!);
    }
  }

  String get _menuQuery => _menuSearchController.text.trim().toLowerCase();

  bool _matchesMenuQuery(String itemName, String sectionTitle) {
    if (_menuQuery.isEmpty) return true;
    return itemName.toLowerCase().contains(_menuQuery) ||
        sectionTitle.toLowerCase().contains(_menuQuery);
  }

  int get _subtotal {
    var total = 0;
    for (final section in kOnlineMenuSections) {
      for (final item in section.items) {
        total += item.price * (_quantities[item.name] ?? 0);
      }
    }
    return total;
  }

  int get _deliveryCharge => _subtotal == 0 ? 0 : 40;

  int get _selectedItemCount {
    var count = 0;
    for (final quantity in _quantities.values) {
      count += quantity;
    }
    return count;
  }

  int get _totalPayable {
    final total = _subtotal + _deliveryCharge - _discountAmount;
    return total < 0 ? 0 : total;
  }

  void _changeQty(MenuItem item, int delta) {
    final current = _quantities[item.name] ?? 0;
    final next = current + delta;
    setState(() {
      if (next <= 0) {
        _quantities.remove(item.name);
      } else {
        _quantities[item.name] = next;
      }
      if (_appliedCoupon != null) {
        _recalculateCoupon();
      }
    });
  }

  void _recalculateCoupon() {
    final code = _appliedCoupon;
    if (code == null) {
      _discountAmount = 0;
      return;
    }
    if (code == 'SAVE10') {
      _discountAmount = (_subtotal * 0.10).round();
    } else if (code == 'WELCOME20') {
      _discountAmount = (_subtotal * 0.20).round();
    } else if (code == 'FLAT100') {
      _discountAmount = _subtotal >= 500 ? 100 : 0;
    }
  }

  void _applyCoupon() {
    final code = _couponController.text.trim().toUpperCase();
    if (code.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter coupon code first.')));
      return;
    }
    if (_subtotal == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add items before applying coupon.')),
      );
      return;
    }

    if (code != 'SAVE10' && code != 'WELCOME20' && code != 'FLAT100') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid coupon code.')));
      return;
    }

    if (code == 'FLAT100' && _subtotal < 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('FLAT100 needs minimum order of INR 500.'),
        ),
      );
      return;
    }

    setState(() {
      _appliedCoupon = code;
      _recalculateCoupon();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$code applied successfully.')));
  }

  void _showOrderConfirmed([String? paymentId]) {
    showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Order Confirmed'),
          content: Text(
            'Thank you, ${_nameController.text.trim()}!\n'
            'Total: INR $_totalPayable\n'
            'Payment: ${_paymentMethod.label}\n'
            'Your order is placed successfully.\n'
            'You will receive it within 30 minutes.\n'
            'Delivery agent will contact you.'
            '${paymentId == null ? '' : '\nPayment ID: $paymentId'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sendCustomerMessage() async {
    final phone = _phoneController.text.trim();
    final body =
        'Restaurant: Your order has been placed successfully. '
        'You will receive it within 30 minutes. '
        'Delivery agent will contact you.';
    final uri = Uri.parse('sms:$phone?body=${Uri.encodeComponent(body)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<bool> _verifyOtpBeforePlaceOrder() async {
    final otp = (100000 + Random().nextInt(900000)).toString();
    var showDemoOtp = false;
    assert(() {
      showDemoOtp = true;
      return true;
    }());
    final otpController = TextEditingController();
    var verified = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('OTP Verification'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('OTP sent to ${_phoneController.text.trim()}'),
              const SizedBox(height: 6),
              if (showDemoOtp)
                Text(
                  'Demo OTP: $otp',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: otpController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Enter OTP',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (otpController.text.trim() == otp) {
                  verified = true;
                  Navigator.of(dialogContext).pop();
                } else {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Invalid OTP.')));
                }
              },
              child: const Text('Verify'),
            ),
          ],
        );
      },
    );
    return verified;
  }

  Future<void> _startUpiPayment() async {
    final amount = _totalPayable.toStringAsFixed(2);
    final txnRef = 'MM${DateTime.now().millisecondsSinceEpoch}';
    final uri = Uri.parse(
      'upi://pay?pa=${Uri.encodeComponent(kMerchantUpiId)}'
      '&pn=${Uri.encodeComponent('Restaurant')}'
      '&tn=${Uri.encodeComponent('Food Order Payment')}'
      '&am=${Uri.encodeComponent(amount)}'
      '&cu=INR&tr=${Uri.encodeComponent(txnRef)}',
    );

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No UPI app found on this device.')),
      );
      return;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dContext) {
        return AlertDialog(
          title: const Text('UPI Payment'),
          content: Text(
            'Payment request opened for UPI ID $kMerchantUpiId\n'
            'Amount: INR $amount\n\n'
            'After completing payment, tap Confirm.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dContext).pop(),
              child: const Text('Confirm Paid'),
            ),
          ],
        );
      },
    );
    await _sendCustomerMessage();
    await _pushBillDeskAlert(
      source: BillDeskAlertSource.onlineDelivery,
      customerName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      itemCount: _selectedItemCount,
      totalAmount: _totalPayable,
      paymentLabel: 'Online Payment',
    );
    _showOrderConfirmed(txnRef);
  }

  Future<void> _placeOrder() async {
    if (_quantities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one menu item.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final verified = await _verifyOtpBeforePlaceOrder();
    if (!verified) return;

    if (_paymentMethod == PaymentMethod.onlinePayment) {
      setState(() => _isPayingOnline = true);
      await _startUpiPayment();
      if (mounted) setState(() => _isPayingOnline = false);
      return;
    }
    await _sendCustomerMessage();
    await _pushBillDeskAlert(
      source: BillDeskAlertSource.onlineDelivery,
      customerName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      itemCount: _selectedItemCount,
      totalAmount: _totalPayable,
      paymentLabel: 'Cash on Delivery',
    );
    _showOrderConfirmed();
  }

  @override
  void dispose() {
    _menuSearchController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _couponController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafePadding = MediaQuery.of(context).viewPadding.bottom;
    return Scaffold(
      appBar: AppBar(title: const Text('Online Order')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomSafePadding),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMenuDetails(),
                    const SizedBox(height: 16),
                    _buildCheckoutDetails(isWide: false),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMenuDetails() {
    final hasAnyMatch = kOnlineMenuSections.any(
      (section) => section.items
          .where((item) => _matchesMenuQuery(item.name, section.title))
          .isNotEmpty,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ModernListHeader(
          title: 'Menu Details',
          subtitle: 'Pick items and adjust quantity quickly.',
          badgeText: 'ONLINE ORDER',
          icon: Icons.shopping_bag_outlined,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _menuSearchController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search food like biryani, desserts...',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        for (final section in kOnlineMenuSections)
          if (section.items
              .where((item) => _matchesMenuQuery(item.name, section.title))
              .isNotEmpty)
            _OrderSection(
              title: section.title,
              items: section.items
                  .where((item) => _matchesMenuQuery(item.name, section.title))
                  .toList(),
              quantities: _quantities,
              onAdd: (item) => _changeQty(item, 1),
              onRemove: (item) => _changeQty(item, -1),
            ),
        if (!hasAnyMatch)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'No matching food items found.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

  Widget _buildCheckoutDetails({required bool isWide}) {
    return Card(
      elevation: isWide ? 1 : 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Details',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Form(
              key: _formKey,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final twoCols = constraints.maxWidth >= 500;
                  if (twoCols) {
                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _nameInput()),
                            const SizedBox(width: 10),
                            Expanded(child: _phoneInput()),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _addressInput(),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      _nameInput(),
                      const SizedBox(height: 10),
                      _phoneInput(),
                      const SizedBox(height: 10),
                      _addressInput(),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            _PaymentMethodCard(
              title: 'Payment Options',
              selectedMethod: _paymentMethod,
              onChanged: (method) {
                setState(() => _paymentMethod = method);
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Coupon Code',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 420) {
                  return Column(
                    children: [
                      _couponInput(),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _applyCoupon,
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: _couponInput()),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _applyCoupon,
                      child: const Text('Apply'),
                    ),
                  ],
                );
              },
            ),
            if (_appliedCoupon != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Applied: $_appliedCoupon',
                  style: const TextStyle(
                    color: Color(0xFFE65100),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 20),
            _SummaryCard(
              subtotal: _subtotal,
              delivery: _deliveryCharge,
              discount: _discountAmount,
              total: _totalPayable,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: _HoverActionButton(
                label: _isPayingOnline
                    ? 'Processing Payment...'
                    : 'Place Your Order Now',
                enabled: !_isPayingOnline,
                onPressed: _placeOrder,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _nameInput() {
    return TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: 'Name',
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter your name';
        }
        return null;
      },
    );
  }

  Widget _phoneInput() {
    return TextFormField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      decoration: const InputDecoration(
        labelText: 'Phone Number',
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (!_isValidIndianPhone(text)) {
          return 'Please enter a valid phone number';
        }
        return null;
      },
    );
  }

  Widget _addressInput() {
    return TextFormField(
      controller: _addressController,
      maxLines: 3,
      decoration: const InputDecoration(
        labelText: 'Delivery Address',
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.trim().length < 8) {
          return 'Please enter full address';
        }
        return null;
      },
    );
  }

  Widget _couponInput() {
    return TextField(
      controller: _couponController,
      textCapitalization: TextCapitalization.characters,
      decoration: const InputDecoration(
        hintText: 'Use SAVE10, WELCOME20, FLAT100',
        border: OutlineInputBorder(),
      ),
    );
  }
}

class _OrderSection extends StatelessWidget {
  const _OrderSection({
    required this.title,
    required this.items,
    required this.quantities,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final List<MenuItem> items;
  final Map<String, int> quantities;
  final ValueChanged<MenuItem> onAdd;
  final ValueChanged<MenuItem> onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (items.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFFFD6B8)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Slide',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFE65100),
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: Color(0xFFE65100),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 305,
            child: Stack(
              children: [
                ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, index) => SizedBox(
                    width: 180,
                    child: _OnlineOrderItemCard(
                      item: items[index],
                      quantity: quantities[items[index].name] ?? 0,
                      onAdd: () => onAdd(items[index]),
                      onRemove: () => onRemove(items[index]),
                    ),
                  ),
                ),
                if (items.length > 1)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 30,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.86),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFFFD6B8)),
                          ),
                          child: const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFFE65100),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnlineOrderItemCard extends StatelessWidget {
  const _OnlineOrderItemCard({
    required this.item,
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final MenuItem item;
  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final displayPrice = item.price == 0
        ? 'Price on request'
        : 'INR ${item.price}';
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFDFC6)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _FoodImage(imageUrl: item.imageUrl),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black45, Colors.black87],
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    displayPrice,
                    style: const TextStyle(
                      color: Color(0xFFFFCC80),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        constraints: const BoxConstraints.tightFor(
                          width: 30,
                          height: 30,
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        splashRadius: 18,
                        color: Colors.white,
                        onPressed: onRemove,
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$quantity',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        constraints: const BoxConstraints.tightFor(
                          width: 30,
                          height: 30,
                        ),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        splashRadius: 18,
                        color: Colors.white,
                        onPressed: onAdd,
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({
    required this.title,
    required this.selectedMethod,
    required this.onChanged,
  });

  final String title;
  final PaymentMethod selectedMethod;
  final ValueChanged<PaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFFFFFAF5),
        border: Border.all(color: const Color(0xFFFFE3CF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PaymentOptionChip(
                label: 'Cash on Delivery',
                selected: selectedMethod == PaymentMethod.cashOnDelivery,
                onTap: () => onChanged(PaymentMethod.cashOnDelivery),
              ),
              _PaymentOptionChip(
                label: 'Online Payment',
                selected: selectedMethod == PaymentMethod.onlinePayment,
                onTap: () => onChanged(PaymentMethod.onlinePayment),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentOptionChip extends StatelessWidget {
  const _PaymentOptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? const Color(0xFFE65100) : Colors.white,
          border: Border.all(
            color: selected ? const Color(0xFFE65100) : const Color(0xFFFFD6B8),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF7A3A14),
          ),
        ),
      ),
    );
  }
}

class _QuickMenuActionTile extends StatelessWidget {
  const _QuickMenuActionTile({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFDFC6)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x12000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFFFF3E0),
                child: Icon(icon, size: 18, color: const Color(0xFFE65100)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Color(0xFFE65100),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE65100) : const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFFE65100) : const Color(0xFFFFD6B8),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: selected ? const Color(0xFF555555) : const Color(0xFFE65100),
          ),
        ),
      ),
    );
  }
}

class _AlertInfoChip extends StatelessWidget {
  const _AlertInfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F0),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFFFE3CF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFFE65100)),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _MenuHoverIcon extends StatefulWidget {
  const _MenuHoverIcon({required this.hasPending});

  final bool hasPending;

  @override
  State<_MenuHoverIcon> createState() => _MenuHoverIconState();
}

class _MenuHoverIconState extends State<_MenuHoverIcon> {
  bool _hovered = false;

  Widget _iconStack({required bool scrolled}) {
    final useGray = _hovered || scrolled;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(
          Icons.menu_rounded,
          color: useGray ? const Color(0xFF6D6D6D) : const Color(0xFFE65100),
        ),
        if (widget.hasPending)
          const Positioned(
            right: -1,
            top: -1,
            child: CircleAvatar(radius: 5, backgroundColor: Colors.red),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final position = Scrollable.maybeOf(context)?.position;
    final iconChild = position == null
        ? _iconStack(scrolled: false)
        : AnimatedBuilder(
            animation: position,
            builder: (_, __) => _iconStack(scrolled: position.pixels > 6),
          );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: iconChild,
    );
  }
}

class _HoverActionButton extends StatefulWidget {
  const _HoverActionButton({
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  State<_HoverActionButton> createState() => _HoverActionButtonState();
}

class _HoverActionButtonState extends State<_HoverActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (!widget.enabled) return;
        setState(() => _hovered = true);
      },
      onExit: (_) {
        if (!widget.enabled) return;
        setState(() => _hovered = false);
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: widget.enabled && _hovered ? 1.02 : 1,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: widget.enabled
                ? const Color(0xFFE65100)
                : Colors.grey.shade400,
            foregroundColor: widget.enabled
                ? Colors.white
                : Colors.white.withValues(alpha: 0.88),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: widget.enabled && _hovered ? 8 : 2,
          ),
          onPressed: widget.enabled ? widget.onPressed : null,
          child: Text(
            widget.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _OrderItemsPanel extends StatelessWidget {
  const _OrderItemsPanel({
    required this.title,
    required this.items,
    required this.totalAmount,
  });

  final String title;
  final List<BookedOrderItem> items;
  final int totalAmount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE3CF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 42,
                      height: 42,
                      child: _FoodImage(imageUrl: _bookMenuImageFor(item.name)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    'x${item.quantity}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'INR ${item.unitPrice * item.quantity}',
                    style: const TextStyle(
                      color: Color(0xFFE65100),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Items: ${items.length}',
                style: const TextStyle(color: Colors.black54),
              ),
              Text(
                'Total: INR $totalAmount',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE65100),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MenuManageItemTile extends StatelessWidget {
  const _MenuManageItemTile({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  final BookMenuItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final displayPrice = item.price == null ? 'N/A' : 'INR ${item.price}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 42,
              height: 42,
              child: _FoodImage(imageUrl: _bookMenuImageForItem(item)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  displayPrice,
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_rounded),
          ),
          IconButton(
            onPressed: onDelete,
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.subtotal,
    required this.delivery,
    required this.discount,
    required this.total,
  });

  final int subtotal;
  final int delivery;
  final int discount;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _SummaryRow(label: 'Subtotal', value: subtotal),
            _SummaryRow(label: 'Delivery', value: delivery),
            _SummaryRow(label: 'Discount', value: -discount),
            const Divider(),
            _SummaryRow(label: 'Total', value: total, highlight: true),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final int value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? const Color(0xFFE65100) : Colors.black87;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          Text(
            'INR $value',
            style: TextStyle(
              fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FoodImage extends StatelessWidget {
  const _FoodImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final isDataImage = imageUrl.startsWith('data:image/');
    final imageBytes = isDataImage
        ? base64Decode(imageUrl.substring(imageUrl.indexOf(',') + 1))
        : null;
    return SizedBox.expand(
      child: isDataImage
          ? Image.memory(
              imageBytes!,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFFFFF3E0),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.fastfood_rounded,
                  size: 30,
                  color: Color(0xFFE65100),
                ),
              ),
            )
          : Image.network(
              imageUrl,
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFFFFF3E0),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.fastfood_rounded,
                  size: 30,
                  color: Color(0xFFE65100),
                ),
              ),
            ),
    );
  }
}

bool _isLegacyCancelledStatus(String? value) {
  return value == 'canceled' || value == 'cancelled';
}

enum PaymentMethod { cashOnDelivery, onlinePayment }

extension PaymentMethodLabel on PaymentMethod {
  String get label {
    switch (this) {
      case PaymentMethod.cashOnDelivery:
        return 'Cash on Delivery';
      case PaymentMethod.onlinePayment:
        return 'Online Payment';
    }
  }
}

class MenuSection {
  const MenuSection({required this.title, required this.items});

  final String title;
  final List<MenuItem> items;
}

class MenuItem {
  const MenuItem({
    required this.name,
    required this.price,
    required this.imageUrl,
  });

  final String name;
  final int price;
  final String imageUrl;
}

enum _HomeMenuAction {
  hotelStaff,
  managerDetails,
  orderHistory,
  billMakerLogin,
  shareApp,
}

enum _BillMakerPortal { orders, menuManagement, alerts }

class _StaffMember {
  const _StaffMember({required this.name, required this.role});

  final String name;
  final String role;
}

class _ManagerInfo {
  const _ManagerInfo({
    required this.name,
    required this.title,
    required this.email,
  });

  final String name;
  final String title;
  final String email;
}

class BookMenuSection {
  const BookMenuSection({required this.title, required this.items});

  final String title;
  final List<BookMenuItem> items;

  BookMenuSection copyWith({String? title, List<BookMenuItem>? items}) {
    return BookMenuSection(
      title: title ?? this.title,
      items: items ?? this.items,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  factory BookMenuSection.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? <dynamic>[];
    return BookMenuSection(
      title: json['title'] as String? ?? '',
      items: rawItems
          .map((item) => BookMenuItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class BookMenuItem {
  const BookMenuItem({required this.name, this.price, this.imageUrl});

  final String name;
  final int? price;
  final String? imageUrl;

  Map<String, dynamic> toJson() {
    return {'name': name, 'price': price, 'imageUrl': imageUrl};
  }

  factory BookMenuItem.fromJson(Map<String, dynamic> json) {
    return BookMenuItem(
      name: json['name'] as String? ?? '',
      price: json['price'] as int?,
      imageUrl: json['imageUrl'] as String?,
    );
  }
}

class BookedOrderItem {
  const BookedOrderItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
  });

  final String name;
  final int quantity;
  final int unitPrice;

  Map<String, dynamic> toJson() {
    return {'name': name, 'quantity': quantity, 'unitPrice': unitPrice};
  }

  factory BookedOrderItem.fromJson(Map<String, dynamic> json) {
    return BookedOrderItem(
      name: json['name'] as String? ?? '',
      quantity: json['quantity'] as int? ?? 0,
      unitPrice: json['unitPrice'] as int? ?? 0,
    );
  }
}

enum BookedOrderStatus { pending, completed, cancelled }

enum BillStatusFilter { all, pending, completed, cancelled }

enum BillDateFilter { today, month, date, all }

enum BillDeskAlertSource { hotelDesk, onlineDelivery }

enum BillDeskAlertSourceFilter { all, hotelDesk, onlineDelivery }

class BillDeskAlert {
  const BillDeskAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.source,
    required this.customerName,
    required this.phone,
    required this.totalAmount,
    required this.itemCount,
    required this.createdAt,
    this.linkedBookedOrderId,
    this.resolved = false,
    this.cloudId,
    this.originDeviceId,
  });

  final int id;
  final String title;
  final String message;
  final BillDeskAlertSource source;
  final String customerName;
  final String phone;
  final int totalAmount;
  final int itemCount;
  final DateTime createdAt;
  final int? linkedBookedOrderId;
  final bool resolved;
  final String? cloudId;
  final String? originDeviceId;

  BillDeskAlert copyWith({int? id, bool? resolved}) {
    return BillDeskAlert(
      id: id ?? this.id,
      title: title,
      message: message,
      source: source,
      customerName: customerName,
      phone: phone,
      totalAmount: totalAmount,
      itemCount: itemCount,
      createdAt: createdAt,
      linkedBookedOrderId: linkedBookedOrderId,
      resolved: resolved ?? this.resolved,
      cloudId: cloudId,
      originDeviceId: originDeviceId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'message': message,
      'source': source.name,
      'customerName': customerName,
      'phone': phone,
      'totalAmount': totalAmount,
      'itemCount': itemCount,
      'createdAt': createdAt.toIso8601String(),
      'linkedBookedOrderId': linkedBookedOrderId,
      'resolved': resolved,
      'cloudId': cloudId,
      'originDeviceId': originDeviceId,
    };
  }

  factory BillDeskAlert.fromJson(Map<String, dynamic> json) {
    final sourceName = json['source'] as String?;
    return BillDeskAlert(
      id: json['id'] as int? ?? 0,
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      source: sourceName == BillDeskAlertSource.onlineDelivery.name
          ? BillDeskAlertSource.onlineDelivery
          : BillDeskAlertSource.hotelDesk,
      customerName: json['customerName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      totalAmount: json['totalAmount'] as int? ?? 0,
      itemCount: json['itemCount'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      linkedBookedOrderId: json['linkedBookedOrderId'] as int?,
      resolved: json['resolved'] as bool? ?? false,
      cloudId: json['cloudId'] as String?,
      originDeviceId: json['originDeviceId'] as String?,
    );
  }

  factory BillDeskAlert.fromCloud(String cloudId, Map<String, dynamic> json) {
    final sourceName = json['source'] as String?;
    return BillDeskAlert(
      id: 0,
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      source: sourceName == BillDeskAlertSource.onlineDelivery.name
          ? BillDeskAlertSource.onlineDelivery
          : BillDeskAlertSource.hotelDesk,
      customerName: json['customerName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      totalAmount: json['totalAmount'] as int? ?? 0,
      itemCount: json['itemCount'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      linkedBookedOrderId: json['linkedBookedOrderId'] as int?,
      resolved: json['resolved'] as bool? ?? false,
      cloudId: cloudId,
      originDeviceId: json['originDeviceId'] as String?,
    );
  }
}

class BookedOrder {
  const BookedOrder({
    required this.id,
    required this.customerName,
    required this.phone,
    required this.items,
    required this.totalAmount,
    required this.createdAt,
    this.status = BookedOrderStatus.pending,
  });

  final int id;
  final String customerName;
  final String phone;
  final List<BookedOrderItem> items;
  final int totalAmount;
  final DateTime createdAt;
  final BookedOrderStatus status;

  BookedOrder copyWith({BookedOrderStatus? status}) {
    return BookedOrder(
      id: id,
      customerName: customerName,
      phone: phone,
      items: items,
      totalAmount: totalAmount,
      createdAt: createdAt,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customerName': customerName,
      'phone': phone,
      'items': items.map((e) => e.toJson()).toList(),
      'totalAmount': totalAmount,
      'createdAt': createdAt.toIso8601String(),
      'status': status.name,
    };
  }

  factory BookedOrder.fromJson(Map<String, dynamic> json) {
    final itemsRaw = (json['items'] as List<dynamic>? ?? <dynamic>[]);
    final statusRaw = json['status'] as String?;
    final legacyConfirmed = json['confirmed'] as bool?;
    final parsedStatus = _isLegacyCancelledStatus(statusRaw)
        ? BookedOrderStatus.cancelled
        : BookedOrderStatus.values
                  .where((s) => s.name == statusRaw)
                  .fold<BookedOrderStatus?>(
                    null,
                    (previous, current) => previous ?? current,
                  ) ??
              (legacyConfirmed == true
                  ? BookedOrderStatus.completed
                  : BookedOrderStatus.pending);
    return BookedOrder(
      id: json['id'] as int? ?? 0,
      customerName: json['customerName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      items: itemsRaw
          .map((e) => BookedOrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalAmount: json['totalAmount'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      status: parsedStatus,
    );
  }
}
