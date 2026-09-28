import 'package:flutter/material.dart';
import '../models/product_check.dart';

/// การ์ดตรวจนับสินค้าก่อนถ่ายรูป
///
/// คนขับอยู่หน้าคลัง ถือมือถือข้างเดียว แตะด้วยนิ้วโป้ง ปุ่มจึงต้องใหญ่
/// และบอกสถานะด้วยสีให้เห็นแวบเดียวว่าเหลือรายการไหนยังไม่ได้ตรวจ
class ProductCheckCard extends StatelessWidget {
  final List<ProductCheckLine> lines;
  final ProductCheckSummary? summary;
  final bool isSaving;
  final void Function(ProductCheckLine line, bool isCorrect) onMark;
  final void Function(ProductCheckLine line) onEditQuantity;
  final VoidCallback onSave;

  const ProductCheckCard({
    super.key,
    required this.lines,
    required this.summary,
    required this.isSaving,
    required this.onMark,
    required this.onEditQuantity,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final checked = lines.where((l) => l.isChecked).length;
    final total = lines.length;
    final allChecked = total > 0 && checked == total;
    final mismatch = lines.where((l) => l.isIncorrect).length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(checked, total, allChecked),
          const Divider(height: 1),
          ...lines.map((line) => _buildLine(context, line)),
          if (mismatch > 0) _buildMismatchNote(mismatch),
          _buildFooter(allChecked),
        ],
      ),
    );
  }

  Widget _buildHeader(int checked, int total, bool allChecked) {
    final color = allChecked ? const Color(0xFF16A34A) : const Color(0xFFEA580C);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              allChecked ? Icons.verified_rounded : Icons.fact_check_outlined,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ตรวจนับสินค้า',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  allChecked
                      ? 'ตรวจครบแล้ว $total รายการ'
                      : 'ตรวจแล้ว $checked จาก $total รายการ',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: total == 0 ? 0 : checked / total,
                  strokeWidth: 4,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation(color),
                ),
                Text(
                  '$checked/$total',
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLine(BuildContext context, ProductCheckLine line) {
    final Color stateColor = line.isCorrect
        ? const Color(0xFF16A34A)
        : line.isIncorrect
            ? const Color(0xFFDC2626)
            : Colors.grey.shade400;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: stateColor, width: 4),
          bottom: BorderSide(color: Colors.grey.shade100),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line.productName,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'สั่ง ${fmt(line.quantity)} ${line.uom}',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              if (line.isIncorrect) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => onEditQuantity(line),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'นับได้ ${fmt(line.checkedQuantity)}'
                      '  (${line.diff > 0 ? '+' : ''}${fmt(line.diff)})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _choice(
                  label: 'ถูกต้อง',
                  icon: Icons.check_circle_outline,
                  selected: line.isCorrect,
                  color: const Color(0xFF16A34A),
                  onTap: () => onMark(line, true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _choice(
                  label: 'ไม่ถูกต้อง',
                  icon: Icons.cancel_outlined,
                  selected: line.isIncorrect,
                  color: const Color(0xFFDC2626),
                  onTap: () => onMark(line, false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _choice({
    required String label,
    required IconData icon,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          border: Border.all(
              color: selected ? color : Colors.grey.shade300, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18, color: selected ? Colors.white : Colors.grey[600]),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMismatchNote(int mismatch) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFB45309), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'มี $mismatch รายการที่นับได้ไม่ตรง — ถ่ายรูปให้เห็นของที่ขาดด้วย',
              style: const TextStyle(fontSize: 13, color: Color(0xFF92400E)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool allChecked) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        height: 48,
        child: ElevatedButton.icon(
          onPressed: (!allChecked || isSaving) ? null : onSave,
          icon: isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_outlined, size: 20),
          label: Text(
            isSaving
                ? 'กำลังบันทึก...'
                : allChecked
                    ? 'บันทึกผลตรวจนับ'
                    : 'ตรวจให้ครบทุกรายการก่อน',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  static String fmt(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }
}
