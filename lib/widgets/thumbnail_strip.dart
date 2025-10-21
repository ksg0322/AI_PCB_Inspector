import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ThumbnailStrip extends StatefulWidget {
  final Function(XFile) onImageSelected;
  final List<XFile> recentImages;
  final Function(Set<String>)? onGenerateReport;
  final List<XFile> selectedImages;
  final Function(XFile)? onImageDeleted;

  const ThumbnailStrip({
    super.key,
    required this.onImageSelected,
    required this.recentImages,
    this.onGenerateReport,
    this.selectedImages = const [],
    this.onImageDeleted,
  });

  @override
  State<ThumbnailStrip> createState() => ThumbnailStripState();
}

class ThumbnailStripState extends State<ThumbnailStrip> {
  final ImagePicker _picker = ImagePicker();
  final Set<String> _selectedImagePaths = {};

  Future<void> _openGallery() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image != null) {
      widget.onImageSelected(image);
    }
  }

  void _toggleImageSelection(String imagePath) {
    setState(() {
      if (_selectedImagePaths.contains(imagePath)) {
        _selectedImagePaths.remove(imagePath);
      } else {
        _selectedImagePaths.add(imagePath);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: Colors.grey[50],
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: widget.recentImages.length + 1, // +1 for the "add" button
        itemBuilder: (context, index) {
          // 마지막 항목: 갤러리 열기 버튼
          if (index >= widget.recentImages.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: _openGallery,
                child: Container(
                  width: 80,
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[400]!, width: 2),
                  ),
                  child: Icon(
                    Icons.add,
                    size: 40,
                    color: Colors.green[700],
                  ),
                ),
              ),
            );
          }

          // 썸네일 항목
          final image = widget.recentImages[index];
          final isSelected = _selectedImagePaths.contains(image.path);
          
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => widget.onImageSelected(image),
              onLongPress: () => _toggleImageSelection(image.path),
              child: Container(
                width: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected ? Border.all(
                    color: Colors.blue[600]!,
                    width: 3,
                  ) : Border.all(
                    color: Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(image.path),
                        fit: BoxFit.cover,
                        width: 80,
                        height: 80,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[50],
                            child: const Icon(
                              Icons.broken_image,
                              color: Colors.green,
                            ),
                          );
                        },
                      ),
                    ),
                    // 선택 표시
                    if (isSelected)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.blue[600],
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    // 삭제 버튼 (X 박스)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () {
                          if (widget.onImageDeleted != null) {
                            widget.onImageDeleted!(image);
                          }
                        },
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(
                              color: Colors.green[400]!,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            Icons.close,
                            color: Colors.green[400],
                            size: 14,
                          ),
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
  
  Set<String> get selectedImagePaths => _selectedImagePaths;
  
  void clearSelection() {
    setState(() {
      _selectedImagePaths.clear();
    });
  }
}

