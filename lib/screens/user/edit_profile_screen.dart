import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/profile_service.dart';
import 'package:loksewa_solution/services/report_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import 'package:loksewa_solution/widgets/auth/floating_label_field.dart';
import 'package:loksewa_solution/widgets/preloading.dart';
import 'package:loksewa_solution/widgets/profile_avatar.dart';
import 'package:loksewa_solution/widgets/subpage_header.dart';
import 'package:loksewa_solution/widgets/syllabus_entrance.dart';

/// §40 Edit Profile — mirrors app/edit-profile.tsx.
///
/// First/last name, email (locked), date of birth, gender and a
/// Cloudinary-hosted profile photo, persisted to users/{uid}.
///
/// Save stays disabled until something actually changes; backing out with
/// unsaved changes asks for confirmation (header back button and the Android
/// system back button alike).
///
/// Camera capture is not offered: this project may not add new dependencies,
/// so the photo sheet offers Gallery (via file_picker) and Remove only.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    this.debugUid,
    this.loadProfile,
    this.saveProfile,
    this.uploadPhoto,
    this.pickPhoto,
  });

  /// Test seam: load/save for this uid instead of the signed-in user, and
  /// never touches AuthService/Firestore/Cloudinary.
  final String? debugUid;

  /// Test seam: replaces the users/{uid} read. Returns the document map.
  final Future<Map<String, dynamic>?> Function(String uid)? loadProfile;

  /// Test seam: replaces the Firestore merge write + auth session sync.
  final Future<void> Function({
    required String uid,
    required String firstName,
    required String lastName,
    String? dob,
    String? gender,
    String? photoURL,
    String? photoURLSource,
  })? saveProfile;

  /// Test seam: replaces the Cloudinary upload. Reports 0..1 progress.
  final Future<String> Function(Uint8List bytes, void Function(double))? uploadPhoto;

  /// Test seam: replaces the file picker. Returns the picked bytes or null.
  final Future<Uint8List?> Function()? pickPhoto;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();

  String? _gender; // 'male' | 'female' | 'other'
  String? _photoURL; // hosted https URL (or null)
  Uint8List? _pickedBytes; // freshly picked local photo, not yet uploaded
  String _email = '';
  bool _pro = false;

  // Snapshot the form is compared against for the dirty check.
  String _initFirst = '';
  String _initLast = '';
  String _initDob = '';
  String? _initGender;
  String? _initPhotoURL;

  bool _hydrated = false;
  bool _minLoaderElapsed = false;
  bool _saving = false;
  String? _savingMessage;
  bool _refreshing = false;
  bool _offline = false;
  String? _dobError;
  double _uploadProgress = 0;
  UploadState _uploadState = UploadState.idle;

  Timer? _minLoaderTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    // The loader stays up briefly so the page opens the same way Course
    // Details does — spinner with a label first, then the real values.
    _minLoaderTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _minLoaderElapsed = true);
    });
    _watchConnectivity();
    _boot();
  }

  @override
  void dispose() {
    _minLoaderTimer?.cancel();
    _connectivitySub?.cancel();
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _dobCtrl.dispose();
    super.dispose();
  }

  Future<void> _watchConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (mounted) _applyConnectivity(results);
    } catch (_) {}
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
          _applyConnectivity,
          // In widget tests there is no platform implementation; the event
          // channel error arrives asynchronously and must not fail the test.
          onError: (_) {});
  }

  void _applyConnectivity(List<ConnectivityResult> results) {
    final offline = results.every((r) => r == ConnectivityResult.none);
    if (mounted && offline != _offline) setState(() => _offline = offline);
  }

  Future<void> _boot() async {
    final uid = widget.debugUid ?? AuthService.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _hydrated = true);
      return;
    }
    try {
      Map<String, dynamic>? doc;
      if (widget.loadProfile != null) {
        doc = await widget.loadProfile!(uid);
      } else {
        final token = await AuthService.getValidIdToken();
        doc = await FirestoreRest.getDocument('users/$uid', idToken: token);
      }
      if (!mounted) return;
      // Seed from the Firestore doc first, then the auth session (covers
      // brand-new Google sign-ins with no doc yet) — like the React screen.
      final sessionUser = AuthService.currentUser;
      final sessionParts = (sessionUser?.displayName ?? '')
          .trim()
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty)
          .toList();
      final firstName = (doc?['firstName'] as String?) ??
          (sessionParts.isNotEmpty ? sessionParts.first : '');
      final lastName = (doc?['lastName'] as String?) ??
          (sessionParts.length > 1 ? sessionParts.skip(1).join(' ') : '');
      setState(() {
        _firstCtrl.text = firstName;
        _lastCtrl.text = lastName;
        _dobCtrl.text = (doc?['dob'] as String?) ?? '';
        final g = doc?['gender'] as String?;
        _gender = g == 'male' || g == 'female' || g == 'other' ? g : null;
        _photoURL = (doc?['photoURL'] as String?) ?? sessionUser?.photoURL;
        _email = sessionUser?.email ?? (doc?['email'] as String?) ?? '';
        _pro = _activePremium(doc);
        _initFirst = _firstCtrl.text;
        _initLast = _lastCtrl.text;
        _initDob = _dobCtrl.text;
        _initGender = _gender;
        _initPhotoURL = _photoURL;
        _hydrated = true;
      });
    } catch (_) {
      // A failed load still hydrates the form (empty) rather than hanging on
      // the spinner — the user can retry via pull-to-refresh.
      if (mounted) setState(() => _hydrated = true);
    }
  }

  /// Same rule as hasActivePremium(): the mirrored entitlement must still be
  /// in date — a lapsed subscription stops decorating immediately.
  bool _activePremium(Map<String, dynamic>? doc) {
    if (doc == null || doc['isPremium'] != true) return false;
    final expiry = doc['premiumExpiryDate'] as String?;
    if (expiry == null) return true;
    final dt = DateTime.tryParse(expiry);
    if (dt == null) return false;
    return dt.isAfter(DateTime.now());
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await _boot();
    if (mounted) setState(() => _refreshing = false);
  }

  bool get _isDirty =>
      _firstCtrl.text != _initFirst ||
      _lastCtrl.text != _initLast ||
      _dobCtrl.text != _initDob ||
      _gender != _initGender ||
      _photoURL != _initPhotoURL ||
      _pickedBytes != null;

  void _attemptLeave() {
    if (_isDirty) {
      _showDiscardDialog();
      return;
    }
    context.pop();
  }

  Future<void> _showDiscardDialog() async {
    final discard = await AppModalShell.show<bool>(
      context: context,
      builder: (ctx) => AppModalShell(
        maxWidth: 360,
        tagLabel: _Strings.discardTitle,
        accent: const Color(0xFFDC2626),
        accentMid: const Color(0xFFF87171),
        accentLight: const Color(0xFFFECACA),
        tagColor: const Color(0xFFDC2626),
        onClose: () => Navigator.of(ctx).pop(false),
        icon: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFFDC2626),
          ),
          child: const Icon(Icons.warning_amber_rounded,
              size: 28, color: Colors.white),
        ),
        title: Text(
          _Strings.discardTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            height: 1.3,
            decoration: TextDecoration.none,
          ),
        ),
        body: Text(
          _Strings.discardMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: Color(0xFF64748B),
            decoration: TextDecoration.none,
          ),
        ),
        footer: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                child: Text(_Strings.keepEditing),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                child: Text(_Strings.discardConfirm),
              ),
            ),
          ],
        ),
      ),
    );
    if (discard == true && mounted) context.pop();
  }

  Future<void> _openPhotoOptions() async {
    final hasPhoto = _pickedBytes != null || _photoURL != null;
    final action = await AppModalShell.show<String>(
      context: context,
      builder: (ctx) => AppModalShell(
        maxWidth: 360,
        tagLabel: _Strings.title,
        onClose: () => Navigator.of(ctx).pop(null),
        icon: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: ExpoPalette.of(ctx).primary,
          ),
          child:
              const Icon(Icons.photo_camera_outlined, size: 28, color: Colors.white),
        ),
        title: Text(
          _Strings.changePhoto,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            height: 1.3,
            decoration: TextDecoration.none,
          ),
        ),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.tonal(
              onPressed: () => Navigator.of(ctx).pop('gallery'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              child: Text(_Strings.gallery),
            ),
            if (hasPhoto) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('remove'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: Text(_Strings.remove),
              ),
            ],
          ],
        ),
        footer: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            child: Text(_Strings.cancel),
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'gallery') {
      await _pickImage();
    } else if (action == 'remove') {
      setState(() {
        _pickedBytes = null;
        _photoURL = null;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      Uint8List? bytes;
      if (widget.pickPhoto != null) {
        bytes = await widget.pickPhoto!();
      } else {
        final result = await FilePicker.platform
            .pickFiles(type: FileType.image, withData: true);
        bytes = result?.files.firstOrNull?.bytes;
      }
      if (bytes != null && bytes.isNotEmpty && mounted) {
        setState(() => _pickedBytes = bytes);
      }
    } catch (_) {
      // A silent failure here is what made this look broken on React —
      // surface it instead.
      if (mounted) showToast(context, _Strings.pickerFailed, ToastVariant.error);
    }
  }

  void _handleDobChange(String raw) {
    final masked = maskDobInput(raw);
    if (masked != _dobCtrl.text) {
      _dobCtrl.value = TextEditingValue(
        text: masked,
        selection: TextSelection.collapsed(offset: masked.length),
      );
    }
    final error =
        masked.length == 10 && !isValidDob(masked) ? _Strings.dobInvalid : null;
    if (error != _dobError) setState(() => _dobError = error);
    // The dirty flag depends on the text; refresh the save button.
    setState(() {});
  }

  Future<void> _handleSave() async {
    final uid = widget.debugUid ?? AuthService.currentUser?.uid;
    if (uid == null || _offline) return;
    if (_firstCtrl.text.trim().isEmpty) {
      showToast(context, _Strings.firstNameRequired, ToastVariant.warning);
      return;
    }
    final dob = _dobCtrl.text;
    if (dob.isNotEmpty && !isValidDob(dob)) {
      setState(() => _dobError = _Strings.dobInvalid);
      return;
    }

    setState(() {
      _saving = true;
      _savingMessage = _Strings.savingProfile;
    });
    try {
      // Only a freshly picked local file needs uploading; an existing https
      // URL (Cloudinary or a Google avatar) is already hosted.
      final photoWasChanged =
          _pickedBytes != null || _photoURL != _initPhotoURL;
      String? resolvedPhotoURL = _photoURL;
      if (_pickedBytes != null) {
        setState(() {
          _uploadState = UploadState.uploading;
          _uploadProgress = 0;
          _savingMessage = _Strings.uploadingPhoto;
        });
        final uploader = widget.uploadPhoto ??
            (bytes, onProgress) => CloudinaryUploader.uploadImage(
                  bytes,
                  onProgress: onProgress,
                );
        resolvedPhotoURL =
            await uploader(_pickedBytes!, (p) {
          if (mounted) setState(() => _uploadProgress = p);
        });
        if (!mounted) return;
        setState(() => _uploadState = UploadState.done);
        showToast(context, _Strings.photoUploaded, ToastVariant.success);
      }

      // A photo selected/removed in Edit Profile is always a manual choice.
      // If the photo was not touched, leave its existing source unchanged so
      // a Google re-login cannot replace a manually uploaded Cloudinary photo.
      final photoURLSource =
          photoWasChanged ? (resolvedPhotoURL != null ? 'manual' : 'none') : null;

      if (widget.saveProfile != null) {
        await widget.saveProfile!(
          uid: uid,
          firstName: _firstCtrl.text,
          lastName: _lastCtrl.text,
          dob: dob.isEmpty ? null : dob,
          gender: _gender,
          photoURL: resolvedPhotoURL,
          photoURLSource: photoURLSource,
        );
      } else {
        final token = await AuthService.getValidIdToken();
        await updateUserProfile(
          uid,
          firstName: _firstCtrl.text,
          lastName: _lastCtrl.text,
          dob: dob.isEmpty ? null : dob,
          gender: _gender,
          photoURL: resolvedPhotoURL,
          photoURLSource: photoURLSource,
          idToken: token,
        );
        // Keep the cached auth session in sync so the Home/Profile headers
        // update immediately without needing a re-login.
        await AuthService.updateCurrentUserProfile(
          displayName: fullNameOf(_firstCtrl.text, _lastCtrl.text),
          photoURL:
              photoWasChanged ? resolvedPhotoURL : AuthService.keepField,
        ).catchError((_) {});
      }

      if (!mounted) return;
      setState(() {
        _initFirst = _firstCtrl.text;
        _initLast = _lastCtrl.text;
        _initDob = _dobCtrl.text;
        _initGender = _gender;
        _initPhotoURL = resolvedPhotoURL;
        _photoURL = resolvedPhotoURL;
        _pickedBytes = null;
        _uploadState = UploadState.idle;
        _dobError = null;
        _savingMessage = null;
      });
      showToast(context, _Strings.updated, ToastVariant.success);
      context.pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _uploadState = UploadState.idle;
          _savingMessage = null;
        });
      }
      showToast(context, _Strings.saveFailed, ToastVariant.error);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _savingMessage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isDirty) _showDiscardDialog();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: Stack(
          children: [
            Column(
              children: [
            SubpageHeader(
              title: _Strings.title,
              onBackPress: _attemptLeave,
            ),
            Expanded(
              child: !_hydrated || !_minLoaderElapsed
                  ? PreloadingWidget(
                      tinted: false,
                      label: _Strings.loadingProfile,
                      hint: _Strings.loadingHint,
                    )
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      color: colors.primary,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          SyllabusEntrance(
                            delayMs: 0,
                            child: _photoBlock(colors),
                          ),
                          const SizedBox(height: 16),
                          SyllabusEntrance(
                            delayMs: 60,
                            child: Column(
                              children: [
                                FloatingLabelField(
                                  label: _Strings.firstName,
                                  controller: _firstCtrl,
                                  leftIcon: Icons.person_outline,
                                  onChanged: (_) => setState(() {}),
                                ),
                                const SizedBox(height: 16),
                                FloatingLabelField(
                                  label: _Strings.lastName,
                                  controller: _lastCtrl,
                                  leftIcon: Icons.person_outline,
                                  onChanged: (_) => setState(() {}),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SyllabusEntrance(
                            delayMs: 120,
                            child: _emailRow(colors),
                          ),
                          const SizedBox(height: 16),
                          SyllabusEntrance(
                            delayMs: 180,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FloatingLabelField(
                                  label: _Strings.dateOfBirth,
                                  controller: _dobCtrl,
                                  leftIcon: Icons.calendar_today_outlined,
                                  keyboardType: TextInputType.number,
                                  errorText: _dobError,
                                  onChanged: _handleDobChange,
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 12, top: 4),
                                  child: Text(
                                    _Strings.dobHint,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SyllabusEntrance(
                            delayMs: 240,
                            child: _genderBlock(colors),
                          ),
                          if (_offline) ...[
                            const SizedBox(height: 12),
                            Text(
                              _Strings.offlineBlocked,
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.warning,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(
                  top: BorderSide(color: colors.divider, width: 0.5),
                ),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        (_isDirty && !_offline && !_saving) ? _handleSave : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_Strings.saveChanges),
                  ),
                ),
              ),
            ),
          ],
        ),
        // Blocks the whole screen while the save is in flight, like
        // React's PageLoaderOverlay.
        if (_saving)
          Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 24),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: colors.primary),
                        const SizedBox(height: 12),
                        Text(
                          _savingMessage ?? _Strings.savingProfile,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Photo with the identity ring (pro sweep / green glow + verified tick on
  /// the name, exactly what Home and Profile show), the upload progress ring
  /// while a photo is in flight, and the camera badge below the photo.
  Widget _photoBlock(ExpoPalette colors) {
    final displayName = fullNameOf(_firstCtrl.text, _lastCtrl.text);
    return Column(
      children: [
        GestureDetector(
          onTap: _openPhotoOptions,
          // Fixed, not shrink-to-fit: the identity ring and the upload
          // progress ring are different thicknesses, so a self-sizing box
          // would shift the avatar and the camera badge by a pixel every
          // time an upload starts or finishes. 110 is the larger of the two
          // (96 + 7 + 7).
          child: SizedBox(
            width: 110,
            height: 110,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _avatarFace(displayName),
                Positioned(
                  bottom: -4,
                  right: -2,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primary,
                      border: Border.all(
                          color: colors.background, width: 2),
                    ),
                    child: const Icon(Icons.camera_alt,
                        size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Live identity preview: the name the user is TYPING, updated in real
        // time, with the verified tick for pro members.
        NameWithTick(
          name: displayName.isEmpty ? _Strings.yourName : displayName,
          pro: _pro,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _Strings.clickPhotoToChange,
          style: TextStyle(
            fontSize: 12,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }

  /// Identity ring at rest, progress ring while uploading. A freshly picked
  /// (not yet uploaded) photo previews from memory with the same ring
  /// treatment ProfileAvatar draws.
  Widget _avatarFace(String displayName) {
    if (_uploadState != UploadState.idle) {
      return AvatarProgressRing(
        size: 96,
        progress: _uploadProgress,
        state: _uploadState,
        child: _pickedFace(96),
      );
    }
    if (_pickedBytes != null) return _pickedFaceWithRing(96);
    return ProfileAvatar(
      uri: _photoURL,
      name: displayName,
      size: 96,
      pro: _pro,
    );
  }

  Widget _pickedFace(double size) => SizedBox(
        width: size,
        height: size,
        child: ClipOval(
          child: Image.memory(
            _pickedBytes!,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        ),
      );

  Widget _pickedFaceWithRing(double size) {
    final face = _pickedFace(size);
    if (_pro) return ProAvatarRing(size: size, child: face);
    // The resting ring ProfileAvatar draws for non-pro users
    // (lib/widgets/profile_avatar.dart).
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF22C55E).withValues(alpha: 0.22),
        border: Border.all(color: const Color(0xFF22C55E), width: 4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF22C55E).withValues(alpha: 0.9),
            blurRadius: 14,
          ),
        ],
      ),
      child: face,
    );
  }

  /// Email — displayed, never editable.
  Widget _emailRow(ExpoPalette colors) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.border, width: 1.5),
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      constraints: const BoxConstraints(minHeight: 58),
      child: Row(
        children: [
          Icon(Icons.mail_outline, size: 20, color: colors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _Strings.emailAddress,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.warning.withValues(alpha: 0x22 / 0xFF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _Strings.editComingSoon,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _genderBlock(ExpoPalette colors) {
    const options = ['male', 'female', 'other'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 8),
          child: Text(
            _Strings.gender,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ),
        Row(
          children: options.map((option) {
            final selected = _gender == option;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                    right: option == 'other' ? 0 : 8),
                child: GestureDetector(
                  onTap: () => setState(() => _gender = option),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? colors.primary
                            : colors.border,
                        width: 1.5,
                      ),
                      color: selected
                          ? colors.primary
                              .withValues(alpha: 0x17 / 0xFF)
                          : colors.surface,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          option == 'male'
                              ? Icons.male
                              : option == 'female'
                                  ? Icons.female
                                  : Icons.transgender,
                          size: 16,
                          color: selected
                              ? colors.primary
                              : colors.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _genderLabel(option),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: selected
                                  ? colors.primary
                                  : colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _genderLabel(String option) {
    switch (option) {
      case 'male':
        return _Strings.genderMale;
      case 'female':
        return _Strings.genderFemale;
      default:
        return _Strings.genderOther;
    }
  }
}

/// Bilingual strings for this screen (mirrors `editProfile`, `loadHints`
/// and `profile.gender_*` in src/core/i18n).
abstract final class _Strings {
  static String get title =>
      AppLanguage.tr('Edit Profile', 'प्रोफाइल सम्पादन गर्नुहोस्');
  static String get loadingProfile =>
      AppLanguage.tr('Loading Your Profile...', 'तपाईंको प्रोफाइल लोड हुँदै...');
  static String get loadingHint => AppLanguage.tr(
      'Fetching your stats and account', 'तपाईंका तथ्याङ्क र खाता ल्याउँदै');
  static String get changePhoto =>
      AppLanguage.tr('Change Photo', 'फोटो परिवर्तन गर्नुहोस्');
  static String get clickPhotoToChange => AppLanguage.tr(
      'Click On Photo To Change', 'फोटोमा क्लिक गरेर परिवर्तन गर्नुहोस्');
  static String get yourName => AppLanguage.tr('Your Name', 'तपाईंको नाम');
  static String get gallery => AppLanguage.tr('Gallery', 'ग्यालरी');
  static String get remove =>
      AppLanguage.tr('Remove Photo', 'फोटो हटाउनुहोस्');
  static String get cancel => AppLanguage.tr('Cancel', 'रद्द गर्नुहोस्');
  static String get saveChanges =>
      AppLanguage.tr('Save Changes', 'परिवर्तनहरू सेव गर्नुहोस्');
  static String get updated => AppLanguage.tr(
      'Profile updated successfully', 'प्रोफाइल सफलतापूर्वक अपडेट भयो');
  static String get offlineBlocked => AppLanguage.tr(
      'Connect to the internet to update your profile',
      'प्रोफाइल अपडेट गर्न इन्टरनेटमा जडान गर्नुहोस्');
  static String get firstName => AppLanguage.tr('First Name', 'पहिलो नाम');
  static String get lastName => AppLanguage.tr('Last Name', 'थर');
  static String get emailAddress =>
      AppLanguage.tr('Email Address', 'इमेल ठेगाना');
  static String get editComingSoon =>
      AppLanguage.tr('Coming soon', 'छिट्टै आउँदै');
  static String get dateOfBirth =>
      AppLanguage.tr('Date of Birth', 'जन्म मिति');
  static String get gender => AppLanguage.tr('Gender', 'लिङ्ग');
  static String get genderMale => AppLanguage.tr('Male', 'पुरुष');
  static String get genderFemale => AppLanguage.tr('Female', 'महिला');
  static String get genderOther => AppLanguage.tr('Other', 'अन्य');
  static String get dobHint =>
      AppLanguage.tr('Format: YYYY-MM-DD', 'ढाँचा: YYYY-MM-DD');
  static String get dobInvalid => AppLanguage.tr(
      'Enter a valid date (YYYY-MM-DD)', 'मान्य मिति हाल्नुहोस् (YYYY-MM-DD)');
  static String get firstNameRequired =>
      AppLanguage.tr('First name is required', 'पहिलो नाम आवश्यक छ');
  static String get saveFailed => AppLanguage.tr(
      'Could not save your profile. Please try again.',
      'प्रोफाइल सेभ भएन। पुनः प्रयास गर्नुहोस्।');
  static String get photoUploaded => AppLanguage.tr(
      'Photo uploaded successfully', 'फोटो सफलतापूर्वक अपलोड भयो');
  static String get uploadingPhoto =>
      AppLanguage.tr('Uploading your photo...', 'फोटो अपलोड हुँदै...');
  static String get savingProfile =>
      AppLanguage.tr('Saving your profile...', 'तपाईंको प्रोफाइल सेभ हुँदै...');
  static String get pickerFailed => AppLanguage.tr(
      'Could not open the photo picker. Please try again.',
      'फोटो पिकर खोल्न सकिएन। पुनः प्रयास गर्नुहोस्।');
  static String get discardTitle =>
      AppLanguage.tr('Discard changes?', 'परिवर्तनहरू हटाउने?');
  static String get discardMessage => AppLanguage.tr(
      'You have unsaved changes. If you go back now they will be lost.',
      'सेभ नभएका परिवर्तनहरू छन्। अहिले फर्कनुभयो भने हराउनेछन्।');
  static String get discardConfirm =>
      AppLanguage.tr('Discard', 'हटाउनुहोस्');
  static String get keepEditing =>
      AppLanguage.tr('Keep editing', 'सम्पादन जारी राख्नुहोस्');
}
