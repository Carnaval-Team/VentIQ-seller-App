class Worker {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String position;
  final String department;
  final String role; // admin, manager, seller, warehouse
  final List<String> permissions;
  final String storeId;
  final String storeName;
  final bool isActive;
  final DateTime hireDate;
  final DateTime? lastLogin;
  final double salary;
  final String workSchedule;

  Worker({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.position,
    required this.department,
    required this.role,
    required this.permissions,
    required this.storeId,
    required this.storeName,
    this.isActive = true,
    required this.hireDate,
    this.lastLogin,
    required this.salary,
    required this.workSchedule,
  });

  factory Worker.fromJson(Map<String, dynamic> json) {
    return Worker(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phone: json['phone'] ?? '',
      position: json['position'] ?? '',
      department: json['department'] ?? '',
      role: json['role'] ?? '',
      permissions: List<String>.from(json['permissions'] ?? []),
      storeId: json['storeId'] ?? '',
      storeName: json['storeName'] ?? '',
      isActive: json['isActive'] ?? true,
      hireDate: DateTime.parse(json['hireDate'] ?? DateTime.now().toIso8601String()),
      lastLogin: json['lastLogin'] != null ? DateTime.parse(json['lastLogin']) : null,
      salary: (json['salary'] ?? 0.0).toDouble(),
      workSchedule: json['workSchedule'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'position': position,
      'department': department,
      'role': role,
      'permissions': permissions,
      'storeId': storeId,
      'storeName': storeName,
      'isActive': isActive,
      'hireDate': hireDate.toIso8601String(),
      'lastLogin': lastLogin?.toIso8601String(),
      'salary': salary,
      'workSchedule': workSchedule,
    };
  }
}

class Permission {
  final String id;
  final String name;
  final String description;
  final String module; // products, inventory, sales, financial, etc.
  final String action; // create, read, update, delete, manage

  Permission({
    required this.id,
    required this.name,
    required this.description,
    required this.module,
    required this.action,
  });

  factory Permission.fromJson(Map<String, dynamic> json) {
    return Permission(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      module: json['module'] ?? '',
      action: json['action'] ?? '',
    );
  }
}

class Role {
  final String id;
  final String name;
  final String description;
  final List<String> permissions;
  final int level; // 1=admin, 2=manager, 3=employee

  Role({
    required this.id,
    required this.name,
    required this.description,
    required this.permissions,
    required this.level,
  });

  factory Role.fromJson(Map<String, dynamic> json) {
    return Role(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      permissions: List<String>.from(json['permissions'] ?? []),
      level: json['level'] ?? 3,
    );
  }
}
