import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Opens the same "choose an image" file picker every `_pickImage` method
/// beside an [ImagePickerBox] uses (Profile/Character/Worldbuilding entries,
/// Notes) — the picker call itself was duplicated verbatim across those
/// widgets; only the attach-to-entity step after it differs per entity type.
Future<String?> pickImagePath() async {
  final result = await FilePicker.pickFiles(
    type: FileType.image,
    dialogTitle: 'Choose an image',
    lockParentWindow: true,
  );
  return result?.files.single.path;
}

/// A square image picker/preview box — an "Add image" placeholder that
/// becomes a thumbnail with a "Remove image" action once one is attached.
/// Shared by every editor that lets the author attach an image to an entity
/// (Characters, Worldbuilding, Notes) via that entity's own service
/// (`attachImage`/`removeImage`/`imageFile`, the same three-method shape on
/// each).
class ImagePickerBox extends StatelessWidget {
  const ImagePickerBox({super.key, required this.imageFile, required this.onPick, this.onRemove});

  final File? imageFile;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onPick,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).dividerColor),
              image: imageFile == null
                  ? null
                  : DecorationImage(image: FileImage(imageFile!), fit: BoxFit.cover),
            ),
            child: imageFile != null
                ? null
                : const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined),
                        SizedBox(height: 4),
                        Text('Add image'),
                      ],
                    ),
                  ),
          ),
        ),
        if (onRemove != null) TextButton(onPressed: onRemove, child: const Text('Remove image')),
      ],
    );
  }
}
