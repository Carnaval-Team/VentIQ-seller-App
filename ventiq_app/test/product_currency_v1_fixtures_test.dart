import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final directory = '../docs/plan-multimoneda';
  final fixtures =
      jsonDecode(
            File(
              '$directory/product_currency_v1_fixtures.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final cases = (fixtures['money_cases'] as List).cast<Map<String, dynamic>>();
  final decimal = RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]*[1-9])?$');
  final money = RegExp(r'^(0|[1-9][0-9]*)\.[0-9]{2}$');

  BigInt cents(String value) {
    expect(money.hasMatch(value), isTrue, reason: value);
    return BigInt.parse(value.replaceAll('.', ''));
  }

  test('fixtures are fictional, versioned and uniquely identified', () {
    expect(fixtures['fictional_only'], isTrue);
    expect(fixtures['contract_version'], 'producto-v1');
    expect(cases, hasLength(14));
    expect(cases.map((c) => c['id']).toSet(), hasLength(cases.length));
  });

  test('financial inputs use exact decimal strings, never JSON numbers', () {
    for (final c in cases) {
      expect(['CUP', 'USD'], contains(c['currency']));
      for (final key in [
        'quantity',
        'unit_price',
        'automatic_value',
        'manual_unit_discount',
        'rate_cup',
      ]) {
        expect(c[key], isA<String>(), reason: '${c['id']}.$key');
        expect(decimal.hasMatch(c[key] as String), isTrue);
      }
      for (final key in ['quantity', 'unit_price', 'rate_cup']) {
        expect(c[key], isNot('0'));
      }
      if (c['currency'] == 'CUP') expect(c['rate_cup'], '1');
      final expected = c['expected'] as Map<String, dynamic>;
      for (final key in [
        'line_gross',
        'subtotal_before_manual',
        'line_net',
        'cup_net',
      ]) {
        expect(money.hasMatch(expected[key] as String), isTrue);
      }
    }
  });

  test('unit price is not multiplied by quantity without adjustments', () {
    for (final c in cases.where(
      (c) => c['automatic_type'] == 'none' && c['manual_unit_discount'] == '0',
    )) {
      expect(
        (c['expected'] as Map)['unit_net'],
        c['unit_price'],
        reason: c['id'] as String,
      );
    }
  });

  test('SQL numeric oracle contains exactly the shared JSON money vectors', () {
    final sql =
        File(
          '$directory/product_currency_v1_fixture_checks.sql',
        ).readAsStringSync();
    final rows =
        sql
            .split('\n')
            .where((line) => line.trimLeft().startsWith("('"))
            .map(
              (line) =>
                  RegExp(
                    "'([^']*)'",
                  ).allMatches(line).map((match) => match.group(1)!).toList(),
            )
            .toList();
    final expectedRows =
        cases.map((c) {
          final e = c['expected'] as Map<String, dynamic>;
          return [
            c['id'],
            c['currency'],
            c['quantity'],
            c['unit_price'],
            c['automatic_type'],
            c['automatic_value'],
            c['manual_unit_discount'],
            c['rate_cup'],
            e['unit_net'],
            e['line_gross'],
            e['subtotal_before_manual'],
            e['manual_nominal'],
            e['line_net'],
            e['cup_net'],
            e['rounding_delta'],
          ];
        }).toList();
    expect(rows, expectedRows);
  });

  test(
    'same currency and method sum native net and historical equivalents',
    () {
      final group = (fixtures['group_cases'] as List).first as Map;
      final totals = <String, List<BigInt>>{};
      for (final line in group['lines'] as List) {
        final key = '${line['currency']}|${line['method_id']}';
        final entry = totals.putIfAbsent(key, () => [BigInt.zero, BigInt.zero]);
        entry[0] += cents(line['net'] as String);
        entry[1] += cents(line['cup_net'] as String);
      }
      final expected = group['expected'] as Map;
      expect(totals.keys.toSet(), expected.keys.toSet());
      for (final key in totals.keys) {
        expect(totals[key]![0], cents(expected[key]['net'] as String));
        expect(totals[key]![1], cents(expected[key]['cup_net'] as String));
      }
      expect(totals['USD|1']![1], isNot(cents('4200.00')));
    },
  );

  test('group sums fixed lines rather than rounding the ideal group again', () {
    final group = (fixtures['group_cases'] as List)[1] as Map;
    final indexed = {for (final c in cases) c['id']: c};
    var native = BigInt.zero;
    var cup = BigInt.zero;
    for (final id in group['line_case_ids'] as List) {
      final e = indexed[id]!['expected'] as Map;
      native += cents(e['line_net'] as String);
      cup += cents(e['cup_net'] as String);
    }
    expect(native, cents(group['expected_native'] as String));
    expect(cup, cents(group['expected_cup'] as String));
    expect(
      native,
      isNot(cents(group['incorrect_rounding_of_ideal_group'] as String)),
    );
  });

  test('example uses stable identities and evidence that cannot be real', () {
    final request = fixtures['request_example'] as Map;
    expect(request['version_monetaria'], fixtures['contract_version']);
    for (final key in ['id_tienda', 'id_tpv', 'id_vendedor']) {
      expect(request[key], isA<String>());
    }
    final line = (request['lineas'] as List).single as Map;
    final payment = (request['pagos'] as List).single as Map;
    expect(line['seleccion_cobro'], {'tipo': 'medio_pago', 'id_medio_pago': 1});
    expect(payment['monto_nativo'], '2.84');
    expect(
      (payment['aplicaciones'] as List).single['id_linea_cliente'],
      line['id_linea_cliente'],
    );
    for (final key in ['snapshot_precio', 'snapshot_tasa']) {
      expect(line[key]['evidencia_publicacion'], startsWith('fixture-only:'));
    }
  });
}
