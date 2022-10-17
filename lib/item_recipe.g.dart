// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'item_recipe.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ItemRecipe _$ItemRecipeFromJson(Map<String, dynamic> json) => ItemRecipe(
      (json['input'] as List<dynamic>)
          .map((e) => ItemAmount.fromJson(e as Map<String, dynamic>))
          .toList(),
      (json['output'] as List<dynamic>)
          .map((e) => ItemAmount.fromJson(e as Map<String, dynamic>))
          .toList(),
      (json['rate'] as num).toDouble(),
      json['building'] as String?,
    );

Map<String, dynamic> _$ItemRecipeToJson(ItemRecipe instance) =>
    <String, dynamic>{
      'input': instance.input.map((e) => e.toJson()).toList(),
      'output': instance.output.map((e) => e.toJson()).toList(),
      'rate': instance.rate,
      'building': instance.building,
    };

ItemAmount _$ItemAmountFromJson(Map<String, dynamic> json) => ItemAmount(
      json['name'] as String,
      (json['amount'] as num).toDouble(),
      byproduct: json['byproduct'] as bool,
    );

Map<String, dynamic> _$ItemAmountToJson(ItemAmount instance) =>
    <String, dynamic>{
      'name': instance.name,
      'amount': instance.amount,
      'byproduct': instance.byproduct,
    };
