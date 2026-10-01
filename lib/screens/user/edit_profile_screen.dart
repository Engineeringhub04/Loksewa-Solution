import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:loksewa_solution/services/app_language.dart';
import 'package:loksewa_solution/services/auth_service.dart';
import 'package:loksewa_solution/services/firestore_rest.dart';
import 'package:loksewa_solution/services/profile_service.dart';
import 'package:loksewa_solution/services/report_service.dart';
import 'package:loksewa_solution/services/theme_service.dart';
import 'package:loksewa_solution/theme/app_theme.dart';
import 'package:loksewa_solution/widgets/app_modal_shell.dart';
import 'package:loksewa_solution/widgets/app_toast.dart';
import 'package:loksewa_solution/widgets/disk_cached_image.dart';
import 'package:loksewa_solution/widgets/preloading.dart';
import 'package:loksewa_solution/widgets/profile_avatar.dart';
import 'package:loksewa_solution/widgets/syllabus_entrance.dart';

/// §40 Edit Profile — mirrors app/edit-profile.tsx.
///
/// First/last name, email (locked), date of birth, gender and a
/// Cloudinary-hosted profile photo, persisted to users/{uid}.
///
/// Design follows the app's premium dark language (dark surfaces, hairline
/// borders, tone-coded icon boxes — same as the Profile tab) instead of the
/// auth-style always-light floating fields.
///
/// Save stays disabled until something actually changes (React:
/// `disabled={!isDirty || isOffline || saving}` — the grey "disabled" look is
/// the correct React behaviour when nothing changed, not a bug); backing out
/// with unsaved changes asks for confirmation (header back button and the
/// Android system back button alike).
///
/// Photo upload state machine — the upload starts IMMEDIATELY when a photo is
/// picked, not at Save:
///
///   idle →(tap photo → sheet → pick)→ uploading →(Cloudinary done)→ done
///     →(900ms beat)→ idle
///
/// - While uploading, the photo's border wears a determinate ring driven by
///   real byte-counted progress events; the picked photo previews from memory
///   inside it. No full-screen overlay covers the ring while it is in flight.
/// - When the upload completes the new photo is set and shown at once; a
///   brief full-green-ring "done" beat follows, then the normal identity ring.
/// - Pick-then-back-out without saving: the screen is disposed without a
///   Firestore write, so the old photoURL stands. The uploaded-but-unused
///   Cloudinary image is an accepted orphan — unsigned presets cannot delete.
/// - Upload failure: error toast, and the photo reverts to the previous one
///   (`_photoURL` is only ever assigned on success).
/// - Save is disabled while an upload is in flight — racing the write against
///   the upload would risk persisting a half-known photoURL.
/// - Offline at pick time: a warning toast and the old photo is kept; there
///   is no silent queue (the user sees exactly what will be saved).
/// - Upload destination matches the React app exactly: Cloudinary unsigned
///   upload, cloud `dw7gg0fhc`, preset `lsphotos`, folder `profile-photos`
///   (see [CloudinaryUploader], mirroring AppConfig.media.cloudinary).
///
/// After a successful save the values are pushed into the shared
/// [ProfileStore] so Home and Profile update in real time — no refresh
/// needed anywhere.
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

  /// Test seam: replaces the photo picker (gallery or camera). Returns the
  /// picked bytes or null.
  final Future<Uint8List?> Function()? pickPhoto;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

/// Where the photo bytes come from.
enum _PhotoSource { gallery, camera }

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();

  String? _gender; // 'male' | 'female' | 'other'
  String? _photoURL; // hosted https URL (or null)
  Uint8List? _pendingPhotoBytes; // picked photo, previewed while uploading
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
  bool _refreshing = false;
  bool _offline = false;
  String? _dobError;

  // Photo upload state (see the state machine in the class doc).
  bool _uploading = false;
  double _uploadProgress = 0;
  UploadState _uploadState = UploadState.idle;

  // Photo geometry: the face is a clean 92px circle, the ring slot is a
  // fixed 106px so the identity ring and the progress ring never shift the
  // layout when they swap, and the outer box leaves breathing room so no
  // ring or badge is ever clipped by its container.
  static const double _faceSize = 92;
  static const double _ringSlot = 106;
  static const double _photoBox = 118;

  Timer? _minLoaderTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    // Header preload: the profile tab already loaded the user's name and
    // photo into the shared ProfileStore when the app opened, so the header
    // (photo + name) renders instantly with zero network wait — only the
    // form fields below hydrate from the fresh read in _boot(). If the store
    // never loaded (or holds another user's data), this is skipped and
    // _boot() does the normal quick load. Skipped for test seams too, so
    // widget tests keep full control of the data.
    final storeProfile = ProfileStore.instance.profile;
    final prefillUid = widget.debugUid ?? AuthService.currentUser?.uid;
    if (widget.loadProfile == null &&
        storeProfile != null &&
        prefillUid != null &&
        storeProfile.uid == prefillUid) {
      _firstCtrl.text = storeProfile.firstName;
      _lastCtrl.text = storeProfile.lastName;
      _photoURL = storeProfile.photoURL;
      _pro = hasActivePremium(storeProfile);
    }
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

  /// A photo counts as changed the moment its upload completes (the upload
  /// starts at pick time, so there is no "picked but not uploaded" state).
  bool get _isDirty =>
      _firstCtrl.text != _initFirst ||
      _lastCtrl.text != _initLast ||
      _dobCtrl.text != _initDob ||
      _gender != _initGender ||
      _photoURL != _initPhotoURL;

  /// Mirrors React's `disabled={!isDirty || isOffline || saving}`, plus the
  /// in-flight upload: saving while bytes are still going out would risk
  /// persisting a half-known photoURL, so the button stays inert until the
  /// upload lands or fails.
  bool get _canSave => _isDirty && !_offline && !_saving && !_uploading;

  void _attemptLeave() {
    if (_isDirty || _uploading) {
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
    if (_uploading) return;
    final hasPhoto = _pendingPhotoBytes != null || _photoURL != null;
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
              onPressed: () => Navigator.of(ctx).pop('camera'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.photo_camera_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text(_Strings.camera),
                ],
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonal(
              onPressed: () => Navigator.of(ctx).pop('gallery'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.photo_library_outlined, size: 20),
                  const SizedBox(width: 8),
                  Text(_Strings.gallery),
                ],
              ),
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
    switch (action) {
      case 'camera':
        await _startPhotoUpload(_PhotoSource.camera);
      case 'gallery':
        await _startPhotoUpload(_PhotoSource.gallery);
      case 'remove':
        setState(() {
          _pendingPhotoBytes = null;
          _photoURL = null;
        });
    }
  }

  /// Picks a photo and uploads it IMMEDIATELY — the upload does not wait for
  /// Save. While the bytes are in flight the picked photo previews from
  /// memory inside the progress ring; `_photoURL` is only assigned when the
  /// upload succeeds, so a failure reverts to the previous photo by itself.
  Future<void> _startPhotoUpload(_PhotoSource source) async {
    if (_uploading) return;
    Uint8List? bytes;
    try {
      if (widget.pickPhoto != null) {
        bytes = await widget.pickPhoto!();
      } else if (source == _PhotoSource.gallery) {
        // System picker via the native channel (no new dependencies).
        // Bytes come back downscaled to ≤1600px JPEG — small, fast uploads.
        bytes = await ScreenshotPicker.pickImage();
      } else {
        // System camera app via the native channel; no CAMERA permission is
        // needed because the camera writes to our own FileProvider URI.
        bytes = await ScreenshotPicker.captureImage();
      }
    } on ScreenshotPickerUnavailable {
      if (mounted) {
        showToast(context, _Strings.pickerFailed, ToastVariant.error);
      }
      return;
    } catch (_) {
      // A silent failure here is what made this look broken on React —
      // surface it instead.
      if (mounted) {
        showToast(context, _Strings.pickerFailed, ToastVariant.error);
      }
      return;
    }
    // Null/empty means the user cancelled the picker — not an error.
    if (bytes == null || bytes.isEmpty || !mounted) return;
    if (_offline) {
      showToast(context, _Strings.photoNeedsInternet, ToastVariant.warning);
      return;
    }

    setState(() {
      _uploading = true;
      _pendingPhotoBytes = bytes;
      _uploadState = UploadState.uploading;
      _uploadProgress = 0;
    });
    try {
      final uploader = widget.uploadPhoto ??
          (b, onProgress) =>
              CloudinaryUploader.uploadImage(b, onProgress: onProgress);
      final url = await uploader(bytes, (p) {
        if (mounted) setState(() => _uploadProgress = p);
      });
      if (!mounted) return;
      // The new photo is set and shown the moment the upload completes —
      // Save only persists what is already visible here.
      setState(() {
        _photoURL = url;
        _pendingPhotoBytes = null;
        _uploading = false;
        _uploadState = UploadState.done;
      });
      showToast(context, _Strings.photoUploaded, ToastVariant.success);
      // The "done" beat: a full green ring around the new photo, then back
      // to the identity ring. The face stays fully visible throughout — no
      // overlay covers it.
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) setState(() => _uploadState = UploadState.idle);
    } catch (_) {
      // `_photoURL` was never assigned, so the previous photo is back on its
      // own — just drop the preview and the ring.
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _pendingPhotoBytes = null;
        _uploadState = UploadState.idle;
        _uploadProgress = 0;
      });
      showToast(context, _Strings.uploadFailed, ToastVariant.error);
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

  /// Persists everything visible on the form — the photo was already
  /// uploaded at pick time, so this is only the Firestore write (plus the
  /// auth session and the shared store).
  Future<void> _handleSave() async {
    final uid = widget.debugUid ?? AuthService.currentUser?.uid;
    if (uid == null || _offline || _uploading) return;
    if (_firstCtrl.text.trim().isEmpty) {
      showToast(context, _Strings.firstNameRequired, ToastVariant.warning);
      return;
    }
    final dob = _dobCtrl.text;
    if (dob.isNotEmpty && !isValidDob(dob)) {
      setState(() => _dobError = _Strings.dobInvalid);
      return;
    }

    setState(() => _saving = true);
    try {
      // A photo selected/removed in Edit Profile is always a manual choice.
      // If the photo was not touched, leave its existing source unchanged so
      // a Google re-login cannot replace a manually uploaded Cloudinary photo.
      final photoWasChanged = _photoURL != _initPhotoURL;
      final photoURLSource =
          photoWasChanged ? (_photoURL != null ? 'manual' : 'none') : null;

      if (widget.saveProfile != null) {
        await widget.saveProfile!(
          uid: uid,
          firstName: _firstCtrl.text,
          lastName: _lastCtrl.text,
          dob: dob.isEmpty ? null : dob,
          gender: _gender,
          photoURL: _photoURL,
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
          photoURL: _photoURL,
          photoURLSource: photoURLSource,
          idToken: token,
        );
        // Keep the cached auth session in sync so the Home/Profile headers
        // update immediately without needing a re-login.
        await AuthService.updateCurrentUserProfile(
          displayName: fullNameOf(_firstCtrl.text, _lastCtrl.text),
          photoURL:
              photoWasChanged ? _photoURL : AuthService.keepField,
        ).catchError((_) {});
      }

      // Push the saved values into the shared store so Home and Profile
      // update immediately — no pull-to-refresh required anywhere. Mirrors
      // React's useProfileStore.getState().applyLocalPatch(...). Written as
      // an explicit constructor (not copyWith) so a cleared DOB really
      // becomes null in the store, like React's object spread.
      final firstName = _firstCtrl.text.trim();
      final lastName = _lastCtrl.text.trim();
      ProfileStore.instance.applyLocalPatch((p) => UserProfile(
            uid: p.uid,
            name: fullNameOf(firstName, lastName),
            firstName: firstName,
            lastName: lastName,
            email: p.email,
            dob: dob.isEmpty ? null : dob,
            gender: _gender,
            photoURL: _photoURL,
            photoURLSource: photoURLSource ?? p.photoURLSource,
            courseId: p.courseId,
            subcourseId: p.subcourseId,
            stats: p.stats,
            isAdmin: p.isAdmin,
            isPremium: p.isPremium,
            premiumPlanName: p.premiumPlanName,
            premiumBillingCycle: p.premiumBillingCycle,
            premiumExpiryDate: p.premiumExpiryDate,
          ));

      if (!mounted) return;
      setState(() {
        _initFirst = _firstCtrl.text;
        _initLast = _lastCtrl.text;
        _initDob = _dobCtrl.text;
        _initGender = _gender;
        _initPhotoURL = _photoURL;
        _dobError = null;
        _uploadState = UploadState.idle;
      });
      showToast(context, _Strings.updated, ToastVariant.success);
      context.pop();
    } catch (_) {
      if (mounted) showToast(context, _Strings.saveFailed, ToastVariant.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExpoPalette.of(context);
    return PopScope(
      canPop: !_isDirty && !_uploading,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && (_isDirty || _uploading)) _showDiscardDialog();
      },
      child: Scaffold(
        backgroundColor: colors.background,
        body: Stack(
          children: [
            Column(
              children: [
                _headerBlock(colors),
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
                            padding:
                                const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            children: [
                              SyllabusEntrance(
                                delayMs: 0,
                                child: Column(
                                  children: [
                                    _ProfileField(
                                      label: _Strings.firstName,
                                      controller: _firstCtrl,
                                      icon: Icons.person_outline,
                                      textInputAction: TextInputAction.next,
                                      onChanged: (_) => setState(() {}),
                                    ),
                                    const SizedBox(height: 12),
                                    _ProfileField(
                                      label: _Strings.lastName,
                                      controller: _lastCtrl,
                                      icon: Icons.person_outline,
                                      textInputAction: TextInputAction.next,
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    _ProfileField(
                                      label: _Strings.dateOfBirth,
                                      controller: _dobCtrl,
                                      icon: Icons.calendar_today_outlined,
                                      keyboardType: TextInputType.number,
                                      maxLength: 10,
                                      errorText: _dobError,
                                      onChanged: _handleDobChange,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                          left: 12, top: 6),
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
                              const SizedBox(height: 20),
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
                        onPressed: _canSave ? _handleSave : null,
                        style: FilledButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
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
            // Only the Firestore-write phase blocks the screen with an
            // overlay. The photo upload never does — its progress ring on the
            // photo is the feedback, and covering it is what made the upload
            // invisible before.
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
                          _Strings.savingProfile,
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

  /// The photo: a clean 92px circle, BoxFit.cover, clipped exactly to its
  /// own circle, wearing exactly ONE ring at a time — the identity ring at
  /// rest (green for free, the premium sweep for pro, like Home/Profile) or
  /// the determinate progress ring while a photo uploads. The rings share a
  /// fixed 106px slot centred in a 118px box with no clipping, so nothing
  /// ever looks cut and the avatar never shifts when the ring swaps.
  /// The big curved header: the shared blue gradient (26px bottom radius,
  /// full-bleed behind the status bar, light status icons — same language as
  /// SubpageHeader) extended downward so it CONTAINS the profile photo, the
  /// live name preview and the "Click On Photo To Change" hint. The form
  /// fields stay below on the page background.
  ///
  /// The photo-upload flow is untouched: tap photo → Gallery/Camera
  /// AppModalShell popup → immediate upload with the circular progress ring.
  /// Name/hint text is white-on-blue so it reads in both app themes.
  Widget _headerBlock(ExpoPalette colors) {
    final displayName = fullNameOf(_firstCtrl.text, _lastCtrl.text);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Container(
        decoration: const BoxDecoration(
          // Solid fallback under the gradient so the header can never render
          // colourless — same stops as the shared SubpageHeader.
          color: Color(0xFF1D4ED8),
          gradient: LinearGradient(
            colors: [
              Color(0xFF2563EB),
              Color(0xFF1D4ED8),
              Color(0xFF0B1F5B),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(26),
            bottomRight: Radius.circular(26),
          ),
        ),
        child: SafeArea(
          top: true,
          bottom: false,
          left: false,
          right: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _headerTopRow(),
                ),
              ),
              const SizedBox(height: 10),
              _photoAvatar(colors),
              const SizedBox(height: 8),
              // Live identity preview: the name the user is TYPING, updated
              // in real time, with the verified tick for pro members.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: NameWithTick(
                  name: displayName.isEmpty ? _Strings.yourName : displayName,
                  pro: _pro,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _photoCaption(),
                style: TextStyle(
                  fontSize: 13,
                  color: _uploading || _uploadState == UploadState.done
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.75),
                  fontWeight: _uploading || _uploadState == UploadState.done
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 22),
            ],
          ),
        ),
      ),
    );
  }

  /// Top row inside the big header: back button / centered title / theme
  /// toggle — the same 36×36 translucent icon boxes as SubpageHeader.
  Widget _headerTopRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget iconBox({Widget? child}) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: child,
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: _attemptLeave,
          child: iconBox(
            child: const Icon(
              Icons.arrow_back,
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
        Expanded(
          child: Text(
            _Strings.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        GestureDetector(
          onTap: () => ThemeService.toggle(context),
          child: iconBox(
            child: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 20,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  /// The tappable photo with its camera badge and upload ring. Behaviour is
  /// identical to before (tap → photo options popup → immediate upload); only
  /// the badge is white-on-blue so it stays visible against the header
  /// gradient instead of blending into it.
  Widget _photoAvatar(ExpoPalette colors) {
    return GestureDetector(
      onTap: _uploading ? null : _openPhotoOptions,
      child: SizedBox(
        width: _photoBox,
        height: _photoBox,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            _avatarFace(fullNameOf(_firstCtrl.text, _lastCtrl.text)),
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _uploading
                    ? SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.primary,
                        ),
                      )
                    : Icon(Icons.camera_alt,
                        size: 16, color: colors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The caption under the photo: live upload percent while bytes are in
  /// flight (the ring shows the fraction), the uploaded confirmation on the
  /// done beat, otherwise the change hint.
  String _photoCaption() {
    if (_uploading) {
      return '${_Strings.uploadingPhoto} ${(_uploadProgress * 100).round()}%';
    }
    if (_uploadState == UploadState.done) return _Strings.photoUploadedShort;
    return _Strings.clickPhotoToChange;
  }

  /// One ring at a time — never stacked. Stacking the identity ring under the
  /// progress ring (plus the old blurred glow being hard-clipped by a tight
  /// box) is what produced the glitchy border the user saw.
  Widget _avatarFace(String displayName) {
    final face = _face(displayName);
    if (_uploadState != UploadState.idle) {
      return SizedBox(
        width: _ringSlot,
        height: _ringSlot,
        child: Center(
          child: AvatarProgressRing(
            size: _faceSize,
            progress: _uploadProgress,
            state: _uploadState,
            child: face,
          ),
        ),
      );
    }
    final ringed = _pro
        ? ProAvatarRing(size: _faceSize, child: face)
        : Container(
            width: _ringSlot,
            height: _ringSlot,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // One clean ring: a solid border with a small clear gap to the
              // photo, no translucent fill and no blurred shadow. The old
              // glow stacked fill + border + shadow and the shadow was cut
              // off by the too-tight outer box — the jagged edge that read
              // as "cut" and "glitchy".
              border:
                  Border.all(color: const Color(0xFF22C55E), width: 3),
            ),
            child: face,
          );
    return SizedBox(
      width: _ringSlot,
      height: _ringSlot,
      child: Center(child: ringed),
    );
  }

  /// The face itself: a 92px circle, clipped exactly to its own bounds so the
  /// photo can never spill under the ring or look cut. While an upload is in
  /// flight the freshly picked photo previews from memory; otherwise the
  /// hosted photo (or initials when there is none).
  Widget _face(String displayName) {
    final pending = _pendingPhotoBytes;
    final Widget inner;
    if (pending != null) {
      inner = Image.memory(
        pending,
        width: _faceSize,
        height: _faceSize,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _initialFace(displayName),
      );
    } else if (_photoURL != null && _photoURL!.isNotEmpty) {
      inner = DiskCachedImage(
        url: _photoURL!,
        width: _faceSize,
        height: _faceSize,
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) => _initialFace(displayName),
      );
    } else {
      inner = _initialFace(displayName);
    }
    return SizedBox(
      width: _faceSize,
      height: _faceSize,
      child: ClipOval(child: inner),
    );
  }

  Widget _initialFace(String displayName) {
    final palette = ExpoPalette.of(context);
    final parts = displayName.trim().split(RegExp(r'\s+'));
    final initials = parts
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return Container(
      width: _faceSize,
      height: _faceSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.surfaceAlt,
      ),
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
          color: palette.primary,
          fontWeight: FontWeight.w600,
          fontSize: 32,
        ),
      ),
    );
  }

  /// Email — displayed, never editable. Locked field with the
  /// "Coming soon" pill, in the profile design language.
  Widget _emailRow(ExpoPalette colors) {
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border, width: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.mail_outline,
                size: 20, color: colors.textSecondary),
          ),
          const SizedBox(width: 10),
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
    // A muted per-theme tone instead of the harsh full-strength blue: the
    // primary mixed 60% toward the neutral text tone stays on-brand in both
    // light and dark without shouting. (lerp moves from the first arg to the
    // second — primary first, like the fields above.)
    final selectedBorder =
        Color.lerp(colors.primary, colors.textSecondary, 0.6)!;
    final selectedIcon =
        Color.lerp(colors.primary, colors.textSecondary, 0.6)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
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
                padding:
                    EdgeInsets.only(right: option == 'other' ? 0 : 8),
                child: GestureDetector(
                  onTap: () => setState(() => _gender = option),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 60),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? selectedBorder : colors.border,
                        width: selected ? 1.25 : 0.5,
                      ),
                      color: selected
                          ? colors.primary.withValues(alpha: 0x14 / 0xFF)
                          : colors.surface,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? colors.primary
                                    .withValues(alpha: 0x14 / 0xFF)
                                : colors.surfaceAlt,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            option == 'male'
                                ? Icons.male
                                : option == 'female'
                                    ? Icons.female
                                    : Icons.transgender,
                            size: 16,
                            color: selected
                                ? selectedIcon
                                : colors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
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
                              color: colors.textPrimary,
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

/// Floating-label text input in the app's premium design language — surface
/// fill, hairline border, tone-coded icon box.
///
/// The focus treatment is deliberately soft: the border and the floating
/// label ease toward a muted per-theme tone (the primary mixed 60% toward
/// the neutral text tone) instead of snapping to full-strength blue, so the
/// fields read premium in both light and dark themes.
///
/// Mirrors FloatingLabelField's motion: the label rests as the placeholder,
/// then floats up and shrinks to 0.82 on focus/value.
class _ProfileField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? errorText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final int? maxLength;

  const _ProfileField({
    required this.label,
    required this.controller,
    required this.icon,
    this.errorText,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.done,
    this.onChanged,
    this.maxLength,
  });

  @override
  State<_ProfileField> createState() => _ProfileFieldState();
}

class _ProfileFieldState extends State<_ProfileField>
    with TickerProviderStateMixin {
  // Two independent drivers, matching React's FloatingLabelField (focusAnim /
  // colorAnim): the POSITION anim floats the label up when the field has
  // focus OR a value; the COLOR anim tints the label + border when the field
  // has focus ONLY. Driving both off one anim made every pre-filled field
  // sit permanently at the blue "focused" tint.
  late final AnimationController _posAnim;
  late final AnimationController _colorAnim;
  late final FocusNode _focusNode;
  bool _focused = false;

  bool get _hasError => widget.errorText != null;
  bool get _hasValue => widget.controller.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _posAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    // Slightly slower colour wash, like React's 240ms colorAnim.
    _colorAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _focusNode = FocusNode();
    if (_hasValue) _posAnim.value = 1.0;
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
  }

  void _onFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
    _drive();
  }

  void _onTextChange() {
    if (!mounted) return;
    setState(() {});
    _drive();
  }

  void _drive() {
    // Position: label floats when focused OR carrying a value.
    if (_focused || _hasValue) {
      _posAnim.animateTo(1.0, curve: Curves.easeOutCubic);
    } else {
      _posAnim.animateTo(0.0, curve: Curves.easeOutCubic);
    }
    // Colour: label + border tint follows focus ONLY.
    if (_focused) {
      _colorAnim.animateTo(1.0, curve: Curves.easeOutCubic);
    } else {
      _colorAnim.animateTo(0.0, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    widget.controller.removeListener(_onTextChange);
    _focusNode.dispose();
    _posAnim.dispose();
    _colorAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ExpoPalette.of(context);
    // Softened focus tone: full-strength primary is the harsh blue the user
    // flagged (React animates the border all the way to it on focus). Mixing
    // the primary 60% toward the neutral text tone keeps the brand readable
    // in light AND dark without the sharp edge. NOTE: Color.lerp(a, b, t)
    // moves FROM a TO b — the primary must be the FIRST argument; the old
    // order (textSecondary, primary, 0.6) was 60% blue and the "softening"
    // never showed up.
    final focusMix =
        Color.lerp(palette.primary, palette.textSecondary, 0.6)!;
    return AnimatedBuilder(
      animation: Listenable.merge([_posAnim, _colorAnim]),
      builder: (context, _) {
        final t = _posAnim.value;
        final c = _colorAnim.value;
        // Unfocused (even with a value) = neutral textSecondary label +
        // neutral border — React parity. The softened focus mix applies
        // only while focused; the harsh full-strength blue stays gone.
        final borderColor = _hasError
            ? palette.danger
            : Color.lerp(palette.border, focusMix, c)!;
        final labelColor = _hasError
            ? palette.danger
            : Color.lerp(palette.textSecondary, focusMix, c)!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: borderColor,
                    width: (_focused || _hasError) ? 1.25 : 0.5),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _hasError
                          ? palette.danger.withValues(alpha: 0x14 / 0xFF)
                          : _focused
                              ? palette.primary
                                  .withValues(alpha: 0x14 / 0xFF)
                              : palette.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.icon,
                      size: 20,
                      color: _hasError
                          ? palette.danger
                          : _focused
                              ? focusMix
                              : palette.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 60,
                      child: Stack(
                        children: [
                          // Floating label — anchored left-center so it never
                          // drifts right as it scales.
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Transform.translate(
                                offset: Offset(0, -17.0 * t),
                                child: Transform.scale(
                                  scale: 1.0 - 0.18 * t,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    widget.label,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: labelColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          TextField(
                            controller: widget.controller,
                            focusNode: _focusNode,
                            keyboardType: widget.keyboardType,
                            textInputAction: widget.textInputAction,
                            maxLength: widget.maxLength,
                            onChanged: widget.onChanged,
                            // The caret defaults to full-strength primary —
                            // the same harsh blue inside the field. It wears
                            // the softened focus tone instead.
                            cursorColor: focusMix,
                            style: TextStyle(
                              fontSize: 16,
                              color: palette.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding:
                                  EdgeInsets.only(top: 20, bottom: 8),
                              // The mask caps the digits anyway; React's
                              // maxLength is semantic parity only.
                              counterText: '',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.errorText != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  widget.errorText!,
                  style: TextStyle(fontSize: 12, color: palette.danger),
                ),
              ),
          ],
        );
      },
    );
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
  static String get camera => AppLanguage.tr('Camera', 'क्यामेरा');
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
  static String get photoNeedsInternet => AppLanguage.tr(
      'Connect to the internet to upload your photo',
      'फोटो अपलोड गर्न इन्टरनेटमा जडान गर्नुहोस्');
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
  static String get photoUploadedShort =>
      AppLanguage.tr('Photo uploaded', 'फोटो अपलोड भयो');
  static String get uploadFailed => AppLanguage.tr(
      'Photo upload failed. Please try again.',
      'फोटो अपलोड असफल भयो। पुनः प्रयास गर्नुहोस्।');
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
