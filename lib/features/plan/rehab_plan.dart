enum PatientCondition { fracture, stroke } // 骨折, 中風

class PlanItem {
  final String exerciseId;
  int order;
  int sets;
  int repsPerSet;
  bool done;

  PlanItem({
    required this.exerciseId,
    required this.order,
    this.sets = 3,
    this.repsPerSet = 10,
    this.done = false,
  });

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'order': order,
        'sets': sets,
        'repsPerSet': repsPerSet,
        'done': done,
      };

  factory PlanItem.fromJson(Map<String, dynamic> json) => PlanItem(
        exerciseId: json['exerciseId'],
        order: json['order'],
        sets: json['sets'],
        repsPerSet: json['repsPerSet'],
        done: json['done'],
      );
}

class RehabPlan {
  final String planId;
  final String createdBy; // "therapist" or "self"
  final DateTime date;
  final List<PlanItem> items;
  final PatientCondition condition;

  RehabPlan({
    required this.planId,
    required this.createdBy,
    required this.date,
    required this.items,
    required this.condition,
  });

  Map<String, dynamic> toJson() => {
        'planId': planId,
        'createdBy': createdBy,
        'date': date.toIso8601String(),
        'items': items.map((i) => i.toJson()).toList(),
        'condition': condition.name,
      };

  factory RehabPlan.fromJson(Map<String, dynamic> json) => RehabPlan(
        planId: json['planId'],
        createdBy: json['createdBy'],
        date: DateTime.parse(json['date']),
        items: (json['items'] as List)
            .map((i) => PlanItem.fromJson(i))
            .toList(),
        condition: PatientCondition.values.byName(json['condition']),
      );
}