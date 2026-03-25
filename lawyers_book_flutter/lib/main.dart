import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LawyersBookApp());
}

class LawyersBookApp extends StatelessWidget {
  const LawyersBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D6E6E)),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lawyers Book',
      theme: baseTheme.copyWith(
        textTheme: GoogleFonts.tajawalTextTheme(baseTheme.textTheme),
        appBarTheme: const AppBarTheme(centerTitle: true),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

enum LawyerAction { edit, delete }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  final DatabaseService _dbService = DatabaseService();

  List<LawyerSummary> _lawyers = <LawyerSummary>[];
  LawyerDetails? _selected;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _initialize() async {
    await _dbService.initialize();
    await _loadLawyers();
  }

  Future<void> _loadLawyers([String? query]) async {
    setState(() {
      _loading = true;
    });

    final List<LawyerSummary> result = await _dbService.searchLawyers(query);
    LawyerDetails? selected = _selected;

    if (result.isNotEmpty) {
      final int preferredId = selected?.id ?? result.first.id;
      selected =
          await _dbService.getLawyerById(preferredId) ??
          await _dbService.getLawyerById(result.first.id);
    } else {
      selected = null;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _lawyers = result;
      _selected = selected;
      _loading = false;
    });
  }

  void _onSearchChanged() {
    _loadLawyers(_searchController.text.trim());
  }

  Future<void> _openAddDialog() async {
    final bool? created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) =>
          LawyerFormSheet(dbService: _dbService, mode: LawyerFormMode.add),
    );

    if (created == true) {
      await _loadLawyers(_searchController.text.trim());
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تمت إضافة المحامي بنجاح')));
    }
  }

  Future<void> _openEditDialog(LawyerDetails details) async {
    final bool? updated = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) => LawyerFormSheet(
        dbService: _dbService,
        mode: LawyerFormMode.edit,
        initial: details,
      ),
    );

    if (updated == true) {
      await _loadLawyers(_searchController.text.trim());
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تحديث بيانات المحامي')));
    }
  }

  Future<void> _deleteLawyer(LawyerSummary lawyer) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('حذف المحامي'),
        content: Text('هل تريد حذف ${lawyer.name}؟'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await _dbService.deleteLawyer(lawyer.id);
    await _loadLawyers(_searchController.text.trim());

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حذف المحامي')));
  }

  Future<void> _exportBackup() async {
    try {
      final File backupFile = await _dbService.exportBackup();
      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('تم تصدير النسخة الاحتياطية'),
          content: SelectableText(backupFile.path),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: backupFile.path));
                if (!context.mounted) {
                  return;
                }
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ مسار الملف')),
                );
              },
              child: const Text('نسخ المسار'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('موافق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تصدير النسخة الاحتياطية: $e')),
      );
    }
  }

  Future<void> _importBackup() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['db'],
      );

      if (result == null || result.files.single.path == null) {
        return;
      }

      final String sourcePath = result.files.single.path!;
      if (!mounted) {
        return;
      }

      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('استيراد نسخة احتياطية'),
          content: const Text(
            'سيتم استبدال البيانات الحالية بالكامل. هل تريد المتابعة؟',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('استيراد'),
            ),
          ],
        ),
      );

      if (confirm != true) {
        return;
      }

      await _dbService.importBackup(sourcePath);
      _searchController.clear();
      await _loadLawyers();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم استيراد النسخة الاحتياطية بنجاح')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل استيراد النسخة الاحتياطية: $e')),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lawyers Book - دليل المحامين'),
          actions: <Widget>[
            IconButton(
              onPressed: _importBackup,
              icon: const Icon(Icons.upload_file_rounded),
              tooltip: 'استيراد نسخة احتياطية',
            ),
            IconButton(
              onPressed: _exportBackup,
              icon: const Icon(Icons.download_rounded),
              tooltip: 'تصدير نسخة احتياطية',
            ),
            IconButton(
              onPressed: _openAddDialog,
              icon: const Icon(Icons.person_add_alt_1),
              tooltip: 'إضافة محامي',
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xFFEAF6F6), Color(0xFFF9FAFC)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'بحث بالاسم، المدينة أو رقم العضوية',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _lawyers.isEmpty
                        ? const Center(child: Text('لا توجد نتائج'))
                        : LayoutBuilder(
                            builder: (BuildContext context, BoxConstraints constraints) {
                              final Widget listPanel = Card(
                                elevation: 0,
                                color: Colors.white,
                                child: ListView.separated(
                                  itemCount: _lawyers.length,
                                  separatorBuilder: (_, __) =>
                                      const Divider(height: 1),
                                  itemBuilder: (BuildContext context, int index) {
                                    final LawyerSummary item = _lawyers[index];
                                    final bool selected =
                                        _selected?.id == item.id;

                                    return ListTile(
                                      selected: selected,
                                      title: Text(item.name),
                                      subtitle: Text(
                                        'العضوية: ${item.membership} | ${item.city}',
                                      ),
                                      trailing: PopupMenuButton<LawyerAction>(
                                        itemBuilder: (BuildContext context) =>
                                            const <
                                              PopupMenuEntry<LawyerAction>
                                            >[
                                              PopupMenuItem<LawyerAction>(
                                                value: LawyerAction.edit,
                                                child: Row(
                                                  children: <Widget>[
                                                    Icon(Icons.edit),
                                                    SizedBox(width: 8),
                                                    Text('تعديل'),
                                                  ],
                                                ),
                                              ),
                                              PopupMenuItem<LawyerAction>(
                                                value: LawyerAction.delete,
                                                child: Row(
                                                  children: <Widget>[
                                                    Icon(Icons.delete),
                                                    SizedBox(width: 8),
                                                    Text('حذف'),
                                                  ],
                                                ),
                                              ),
                                            ],
                                        onSelected:
                                            (LawyerAction action) async {
                                              if (action == LawyerAction.edit) {
                                                final LawyerDetails? details =
                                                    await _dbService
                                                        .getLawyerById(item.id);
                                                if (details != null) {
                                                  await _openEditDialog(
                                                    details,
                                                  );
                                                }
                                                return;
                                              }
                                              await _deleteLawyer(item);
                                            },
                                      ),
                                      onTap: () async {
                                        final LawyerDetails? details =
                                            await _dbService.getLawyerById(
                                              item.id,
                                            );
                                        if (!mounted) {
                                          return;
                                        }
                                        setState(() {
                                          _selected = details;
                                        });
                                      },
                                    );
                                  },
                                ),
                              );

                              final Widget detailsPanel = LawyerDetailsCard(
                                details: _selected,
                              );

                              if (constraints.maxWidth < 900) {
                                return Column(
                                  children: <Widget>[
                                    Expanded(flex: 6, child: listPanel),
                                    const SizedBox(height: 10),
                                    Expanded(flex: 5, child: detailsPanel),
                                  ],
                                );
                              }

                              return Row(
                                children: <Widget>[
                                  Expanded(flex: 6, child: listPanel),
                                  const SizedBox(width: 12),
                                  Expanded(flex: 5, child: detailsPanel),
                                ],
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openAddDialog,
          icon: const Icon(Icons.add),
          label: const Text('إضافة'),
        ),
      ),
    );
  }
}

class LawyerDetailsCard extends StatelessWidget {
  const LawyerDetailsCard({super.key, required this.details});

  final LawyerDetails? details;

  @override
  Widget build(BuildContext context) {
    final LawyerDetails? d = details;
    if (d == null) {
      return const Card(child: Center(child: Text('اختر محامي لعرض التفاصيل')));
    }

    final List<MapEntry<String, String>> rows = <MapEntry<String, String>>[
      MapEntry<String, String>('الاسم الكامل', d.name),
      MapEntry<String, String>('رقم العضوية', d.membership),
      MapEntry<String, String>('المدينة', d.city),
      MapEntry<String, String>('رقم الجوال', d.phone),
      MapEntry<String, String>('رقم الهاتف', d.telephone),
      MapEntry<String, String>('الفاكس', d.fax),
      MapEntry<String, String>('البريد الإلكتروني', d.email),
      MapEntry<String, String>('العنوان', d.address),
    ];

    return Card(
      color: const Color(0xFFFDFEFF),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: ListView(
          children: rows
              .map(
                (MapEntry<String, String> e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        e.key,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        e.value.isEmpty ? '-' : e.value,
                        textAlign: TextAlign.start,
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

enum LawyerFormMode { add, edit }

class LawyerFormSheet extends StatefulWidget {
  const LawyerFormSheet({
    super.key,
    required this.dbService,
    required this.mode,
    this.initial,
  });

  final DatabaseService dbService;
  final LawyerFormMode mode;
  final LawyerDetails? initial;

  @override
  State<LawyerFormSheet> createState() => _LawyerFormSheetState();
}

class _LawyerFormSheetState extends State<LawyerFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _membership;
  late final TextEditingController _city;
  late final TextEditingController _phone;
  late final TextEditingController _telephone;
  late final TextEditingController _fax;
  late final TextEditingController _email;
  late final TextEditingController _address;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final LawyerDetails? initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _membership = TextEditingController(text: initial?.membership ?? '');
    _city = TextEditingController(text: initial?.city ?? '');
    _phone = TextEditingController(text: initial?.phone ?? '');
    _telephone = TextEditingController(text: initial?.telephone ?? '');
    _fax = TextEditingController(text: initial?.fax ?? '');
    _email = TextEditingController(text: initial?.email ?? '');
    _address = TextEditingController(text: initial?.address ?? '');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _saving = true;
    });

    if (widget.mode == LawyerFormMode.add) {
      await widget.dbService.addLawyer(
        name: _name.text.trim(),
        membership: _membership.text.trim(),
        city: _city.text.trim(),
        phone: _phone.text.trim(),
        telephone: _telephone.text.trim(),
        fax: _fax.text.trim(),
        email: _email.text.trim(),
        address: _address.text.trim(),
      );
    } else {
      await widget.dbService.updateLawyer(
        id: widget.initial!.id,
        name: _name.text.trim(),
        membership: _membership.text.trim(),
        city: _city.text.trim(),
        phone: _phone.text.trim(),
        telephone: _telephone.text.trim(),
        fax: _fax.text.trim(),
        email: _email.text.trim(),
        address: _address.text.trim(),
      );
    }

    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _name.dispose();
    _membership.dispose();
    _city.dispose();
    _phone.dispose();
    _telephone.dispose();
    _fax.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomInset + 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _field(_name, 'الاسم الكامل', requiredField: true),
              _field(_membership, 'رقم العضوية', requiredField: true),
              _field(_city, 'المدينة'),
              _field(_phone, 'رقم الجوال'),
              _field(_telephone, 'رقم الهاتف'),
              _field(_fax, 'الفاكس'),
              _field(_email, 'البريد الإلكتروني'),
              _field(_address, 'العنوان', maxLines: 2),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(
                    widget.mode == LawyerFormMode.add ? 'إضافة' : 'حفظ',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool requiredField = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
        validator: (String? value) {
          if (requiredField && (value == null || value.trim().isEmpty)) {
            return 'هذا الحقل مطلوب';
          }
          return null;
        },
      ),
    );
  }
}

class LawyerSummary {
  LawyerSummary({
    required this.id,
    required this.membership,
    required this.city,
    required this.name,
  });

  final int id;
  final String membership;
  final String city;
  final String name;

  factory LawyerSummary.fromRow(Map<String, Object?> row) {
    return LawyerSummary(
      id: (row['ID'] as num?)?.toInt() ?? 0,
      membership: (row['Membership'] ?? '').toString(),
      city: (row['City'] ?? '').toString(),
      name: ((row['ArFullName'] ?? row['FullName']) ?? '').toString(),
    );
  }
}

class LawyerDetails {
  LawyerDetails({
    required this.id,
    required this.name,
    required this.membership,
    required this.city,
    required this.phone,
    required this.telephone,
    required this.fax,
    required this.email,
    required this.address,
  });

  final int id;
  final String name;
  final String membership;
  final String city;
  final String phone;
  final String telephone;
  final String fax;
  final String email;
  final String address;

  factory LawyerDetails.fromRow(Map<String, Object?> row) {
    return LawyerDetails(
      id: (row['ID'] as num?)?.toInt() ?? 0,
      name: ((row['ArFullName'] ?? row['FullName']) ?? '').toString(),
      membership: (row['Membership'] ?? '').toString(),
      city: ((row['ArCity'] ?? row['City']) ?? '').toString(),
      phone: (row['Phone'] ?? '').toString(),
      telephone: (row['Telephone'] ?? '').toString(),
      fax: (row['Fax'] ?? '').toString(),
      email: (row['Email'] ?? '').toString(),
      address: ((row['ArAddress'] ?? row['Address']) ?? '').toString(),
    );
  }
}

class DatabaseService {
  Database? _db;
  String? _dbPath;

  Future<void> initialize() async {
    if (_db != null) {
      return;
    }

    final Directory docsDir = await getApplicationDocumentsDirectory();
    final String dbPath = p.join(docsDir.path, 'lawyers.db');
    _dbPath = dbPath;
    final File dbFile = File(dbPath);

    if (!await dbFile.exists()) {
      final ByteData data = await rootBundle.load('assets/data/lawyers.db');
      final List<int> bytes = data.buffer.asUint8List();
      await dbFile.writeAsBytes(bytes, flush: true);
    }

    _db = await openDatabase(dbPath);
  }

  Future<List<LawyerSummary>> searchLawyers(String? query) async {
    final Database db = _db!;

    final List<Map<String, Object?>> rows;
    final String q = (query ?? '').trim();
    if (q.isEmpty) {
      rows = await db.rawQuery(
        'SELECT ID, Membership, City, ArFullName, FullName FROM lawyers ORDER BY ID DESC LIMIT 100',
      );
    } else {
      rows = await db.rawQuery(
        'SELECT ID, Membership, City, ArFullName, FullName FROM lawyers '
        'WHERE FullName LIKE ? OR ArFullName LIKE ? OR City LIKE ? OR ArCity LIKE ? OR Membership LIKE ? '
        'ORDER BY ID DESC LIMIT 100',
        <Object>['%$q%', '%$q%', '%$q%', '%$q%', '%$q%'],
      );
    }
    return rows.map(LawyerSummary.fromRow).toList();
  }

  Future<LawyerDetails?> getLawyerById(int id) async {
    final Database db = _db!;
    final List<Map<String, Object?>> rows = await db.rawQuery(
      'SELECT * FROM lawyers WHERE ID = ? LIMIT 1',
      <Object>[id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return LawyerDetails.fromRow(rows.first);
  }

  Future<void> addLawyer({
    required String name,
    required String membership,
    required String city,
    required String phone,
    required String telephone,
    required String fax,
    required String email,
    required String address,
  }) async {
    final Database db = _db!;
    await db.rawInsert(
      'INSERT INTO lawyers (FullName, ArFullName, Membership, City, ArCity, Phone, Telephone, Fax, Email, ArAddress, Address) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object>[
        name,
        name,
        membership,
        city,
        city,
        phone,
        telephone,
        fax,
        email,
        address,
        address,
      ],
    );
  }

  Future<void> updateLawyer({
    required int id,
    required String name,
    required String membership,
    required String city,
    required String phone,
    required String telephone,
    required String fax,
    required String email,
    required String address,
  }) async {
    final Database db = _db!;
    await db.rawUpdate(
      'UPDATE lawyers SET '
      'FullName = ?, ArFullName = ?, Membership = ?, City = ?, ArCity = ?, '
      'Phone = ?, Telephone = ?, Fax = ?, Email = ?, ArAddress = ?, Address = ? '
      'WHERE ID = ?',
      <Object>[
        name,
        name,
        membership,
        city,
        city,
        phone,
        telephone,
        fax,
        email,
        address,
        address,
        id,
      ],
    );
  }

  Future<void> deleteLawyer(int id) async {
    final Database db = _db!;
    await db.rawDelete('DELETE FROM lawyers WHERE ID = ?', <Object>[id]);
  }

  Future<File> exportBackup() async {
    final String sourcePath = _dbPath!;
    final File sourceFile = File(sourcePath);

    Directory? outputDir;
    try {
      outputDir = await getDownloadsDirectory();
    } catch (_) {
      outputDir = null;
    }

    outputDir ??= await getExternalStorageDirectory();
    outputDir ??= await getApplicationDocumentsDirectory();
    await outputDir.create(recursive: true);

    final String stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final String outputPath = p.join(
      outputDir.path,
      'lawyers_backup_$stamp.db',
    );
    return sourceFile.copy(outputPath);
  }

  Future<void> importBackup(String sourcePath) async {
    final File sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('الملف المحدد غير موجود');
    }

    final String targetPath = _dbPath!;
    final File targetFile = File(targetPath);

    await _db?.close();
    _db = null;

    await sourceFile.copy(targetFile.path);
    _db = await openDatabase(targetPath);
  }
}
