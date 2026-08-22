/// Организация, в которую вошли. Данные принадлежат ей, а не человеку.
class Organization {
  const Organization({required this.id, required this.name});

  factory Organization.fromJson(Map<String, dynamic> json) =>
      Organization(id: json['id'] as int, name: (json['name'] ?? '') as String);

  final int id;
  final String name;
}

/// Роль в организации. Владелец и администратор ведут её, менеджер работает.
enum Role { owner, admin, manager }

class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.organization,
    required this.managesOrganization,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: json['id'] as int,
    email: (json['email'] ?? '') as String,
    name: (json['name'] ?? '') as String,
    role: Role.values.firstWhere(
      (role) => role.name == json['role'],
      orElse: () => Role.manager,
    ),
    organization: Organization.fromJson(
      Map<String, dynamic>.from(json['organization'] as Map),
    ),
    managesOrganization: (json['manages_organization'] ?? false) as bool,
  );

  final int id;
  final String email;
  final String name;
  final Role role;
  final Organization organization;

  /// По ней решаем, показывать ли то, чем ведут организацию.
  final bool managesOrganization;

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'role': role.name,
    'organization': {'id': organization.id, 'name': organization.name},
    'manages_organization': managesOrganization,
  };
}
