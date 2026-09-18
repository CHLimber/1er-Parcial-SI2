import { jsPDF } from 'jspdf';
import autoTable from 'jspdf-autotable';
import * as XLSX from 'xlsx';

/**
 * CU15 - Exportacion de reportes. Todo corre en el navegador (jsPDF + jspdf-autotable para PDF,
 * SheetJS para Excel): los datos ya estan en los signals de panel-reportes.page.ts porque el
 * usuario ya los pidio para verlos en pantalla, asi que no hace falta un endpoint nuevo en el
 * backend solo para exportar lo mismo de otra forma.
 *
 * "Graficas" (con canvases de Chart.js) solo exporta a PDF via exportarGraficasPdf, que vuelca
 * cada grafico como imagen (Chart.toBase64Image()) -- no tiene version Excel a pedido explicito
 * del usuario. "Estaticos", "Dinamicos" e "IA" son tablas: usan exportarTablaPdf/exportarTablaExcel.
 */

const COLOR_FLAME: [number, number, number] = [193, 81, 107];

export interface ColumnaExportable {
  clave: string;
  etiqueta: string;
}

function formatearValor(valor: unknown): string {
  if (valor === null || valor === undefined) return '';
  if (typeof valor === 'number') return valor.toLocaleString('es-BO', { maximumFractionDigits: 2 });
  return String(valor);
}

function nombreConFecha(base: string): string {
  return `${base}-${new Date().toISOString().slice(0, 10)}`;
}

export function exportarTablaPdf(
  titulo: string,
  columnas: ColumnaExportable[],
  filas: Record<string, unknown>[],
  nombreArchivo: string,
): void {
  const doc = new jsPDF();
  doc.setFontSize(14);
  doc.text(titulo, 14, 16);
  doc.setFontSize(9);
  doc.setTextColor(120);
  doc.text(`FashionStore — generado ${new Date().toLocaleString('es-BO')}`, 14, 22);
  doc.setTextColor(0);

  autoTable(doc, {
    startY: 28,
    head: [columnas.map((c) => c.etiqueta)],
    body: filas.map((fila) => columnas.map((c) => formatearValor(fila[c.clave]))),
    styles: { fontSize: 8, cellPadding: 2 },
    headStyles: { fillColor: COLOR_FLAME },
    alternateRowStyles: { fillColor: [250, 245, 242] },
  });

  doc.save(`${nombreConFecha(nombreArchivo)}.pdf`);
}

export function exportarTablaExcel(
  titulo: string,
  columnas: ColumnaExportable[],
  filas: Record<string, unknown>[],
  nombreArchivo: string,
): void {
  const datos = filas.map((fila) => {
    const objeto: Record<string, unknown> = {};
    for (const columna of columnas) objeto[columna.etiqueta] = fila[columna.clave] ?? '';
    return objeto;
  });
  const hoja = XLSX.utils.json_to_sheet(datos);
  const libro = XLSX.utils.book_new();
  const nombreHoja = titulo.replace(/[\\/*?:[\]]/g, '').slice(0, 31) || 'Reporte';
  XLSX.utils.book_append_sheet(libro, hoja, nombreHoja);
  XLSX.writeFile(libro, `${nombreConFecha(nombreArchivo)}.xlsx`);
}

export interface SeccionGraficaExportable {
  titulo: string;
  imagen?: string;
}

export interface KpiExportable {
  etiqueta: string;
  valor: string;
}

export function exportarGraficasPdf(
  titulo: string,
  kpis: KpiExportable[],
  secciones: SeccionGraficaExportable[],
  nombreArchivo: string,
): void {
  const doc = new jsPDF();
  doc.setFontSize(16);
  doc.text(titulo, 14, 18);
  doc.setFontSize(9);
  doc.setTextColor(120);
  doc.text(`FashionStore — generado ${new Date().toLocaleString('es-BO')}`, 14, 24);
  doc.setTextColor(0);

  let y = 32;
  if (kpis.length) {
    autoTable(doc, {
      startY: y,
      head: [['Indicador', 'Valor']],
      body: kpis.map((k) => [k.etiqueta, k.valor]),
      styles: { fontSize: 9, cellPadding: 2.5 },
      headStyles: { fillColor: COLOR_FLAME },
    });
    // jspdf-autotable adjunta lastAutoTable en runtime; no tiene tipado propio en esta version.
    y = (doc as unknown as { lastAutoTable: { finalY: number } }).lastAutoTable.finalY + 10;
  }

  const anchoImagen = 180;
  const altoImagen = 85;
  const altoPagina = doc.internal.pageSize.getHeight();

  for (const seccion of secciones) {
    if (!seccion.imagen) continue;
    if (y + altoImagen + 14 > altoPagina) {
      doc.addPage();
      y = 18;
    }
    doc.setFontSize(11);
    doc.text(seccion.titulo, 14, y);
    doc.addImage(seccion.imagen, 'PNG', 14, y + 4, anchoImagen, altoImagen);
    y += altoImagen + 16;
  }

  doc.save(`${nombreConFecha(nombreArchivo)}.pdf`);
}
