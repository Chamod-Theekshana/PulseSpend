import 'dart:convert';
import 'package:flutter/material.dart';

ImageProvider getProfileImageProvider(String url) {
  if (url.startsWith('data:image')) {
    final parts = url.split(',');
    if (parts.length > 1) {
      return MemoryImage(base64Decode(parts[1]));
    }
  }
  return NetworkImage(url);
}
