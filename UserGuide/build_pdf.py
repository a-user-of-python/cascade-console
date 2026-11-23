#!/usr/bin/env python3
"""Build CascadeConsole-UserGuide.pdf from CascadeConsole-UserGuide.md.
Simple, purpose-built Markdown -> ReportLab converter for this guide only.
High contrast, generous leading, natural type sizes."""
import re, sys
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.units import inch
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT
from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph,
                                Spacer, PageBreak, KeepTogether, Table, TableStyle,
                                Preformatted)

SRC = sys.argv[1] if len(sys.argv) > 1 else "CascadeConsole-UserGuide.md"
OUT = sys.argv[2] if len(sys.argv) > 2 else "CascadeConsole-UserGuide.pdf"

INK = colors.HexColor("#111111")
ACCENT = colors.HexColor("#0B3D91")
CODEBG = colors.HexColor("#EEF1F4")
RULE = colors.HexColor("#0B3D91")

S = {
    "h1": ParagraphStyle("h1", fontName="Helvetica-Bold", fontSize=20, leading=25,
                         textColor=ACCENT, spaceBefore=6, spaceAfter=10),
    "h2": ParagraphStyle("h2", fontName="Helvetica-Bold", fontSize=14.5, leading=19,
                         textColor=INK, spaceBefore=14, spaceAfter=6),
    "h3": ParagraphStyle("h3", fontName="Helvetica-Bold", fontSize=12.5, leading=17,
                         textColor=INK, spaceBefore=10, spaceAfter=4),
    "body": ParagraphStyle("body", fontName="Helvetica", fontSize=11.5, leading=17.5,
                           textColor=INK, spaceAfter=7, alignment=TA_LEFT),
    "bullet": ParagraphStyle("bullet", parent=None, fontName="Helvetica", fontSize=11.5,
                             leading=17.5, textColor=INK, leftIndent=16, bulletIndent=4,
                             spaceAfter=4),
    "num": ParagraphStyle("num", fontName="Helvetica", fontSize=11.5, leading=17.5,
                          textColor=INK, leftIndent=16, spaceAfter=4),
    "code": ParagraphStyle("code", fontName="Courier", fontSize=10, leading=14.5,
                           textColor=INK),
    "quote": ParagraphStyle("quote", fontName="Helvetica-Oblique", fontSize=11.5,
                            leading=17.5, textColor=INK, leftIndent=14, spaceAfter=7),
    "cell": ParagraphStyle("cell", fontName="Helvetica", fontSize=10.5, leading=14.5,
                           textColor=INK),
    "cellb": ParagraphStyle("cellb", fontName="Helvetica-Bold", fontSize=10.5,
                            leading=14.5, textColor=colors.white),
    "title": ParagraphStyle("title", fontName="Helvetica-Bold", fontSize=27, leading=33,
                            textColor=ACCENT, spaceAfter=8),
    "subtitle": ParagraphStyle("subtitle", fontName="Helvetica", fontSize=15, leading=21,
                               textColor=INK, spaceAfter=6),
}

def esc(t):
    return t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

def inline(t):
    t = esc(t)
    t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)
    t = re.sub(r"`([^`]+)`", r'<font face="Courier" size="10.5">\1</font>', t)
    t = re.sub(r"\*([^*]+)\*", r"<i>\1</i>", t)
    return t

lines = open(SRC, encoding="utf-8").read().splitlines()
story = []
i = 0
first_h1 = True
title_done = False

def code_block(buf):
    txt = "\n".join(buf)
    p = Preformatted(txt, S["code"])
    t = Table([[p]], colWidths=[7.0 * inch])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), CODEBG),
        ("LEFTPADDING", (0, 0), (-1, -1), 10), ("RIGHTPADDING", (0, 0), (-1, -1), 10),
        ("TOPPADDING", (0, 0), (-1, -1), 8), ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
        ("BOX", (0, 0), (-1, -1), 0.6, colors.HexColor("#B9C2CC")),
    ]))
    return [t, Spacer(1, 8)]

while i < len(lines):
    ln = lines[i]
    # code fence
    if ln.strip().startswith("```"):
        buf = []
        i += 1
        while i < len(lines) and not lines[i].strip().startswith("```"):
            buf.append(lines[i]); i += 1
        i += 1
        story.extend(code_block(buf))
        continue
    # table
    if ln.strip().startswith("|") and i + 1 < len(lines) and re.match(r"^\|[\s:\-|]+\|$", lines[i + 1].strip()):
        rows = []
        header = [c.strip() for c in ln.strip().strip("|").split("|")]
        rows.append([Paragraph(inline(c), S["cellb"]) for c in header])
        i += 2
        while i < len(lines) and lines[i].strip().startswith("|"):
            cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
            while len(cells) < len(header):
                cells.append("")
            rows.append([Paragraph(inline(c), S["cell"]) for c in cells[:len(header)]])
            i += 1
        ncol = len(header)
        w = 7.0 * inch / ncol
        widths = [w] * ncol
        if ncol >= 3:
            widths[0] = 1.35 * inch
            rest = (7.0 * inch - widths[0]) / (ncol - 1)
            widths = [widths[0]] + [rest] * (ncol - 1)
        t = Table(rows, colWidths=widths, repeatRows=1)
        t.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), ACCENT),
            ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#8A97A5")),
            ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#F4F6F8")]),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 6), ("RIGHTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 5), ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ]))
        story.extend([t, Spacer(1, 10)])
        continue
    # headings
    m = re.match(r"^(#{1,3})\s+(.*)$", ln)
    if m:
        level, text = len(m.group(1)), m.group(2).strip()
        if level == 1:
            if not title_done:
                story.append(Paragraph("Cascade Console", S["title"]))
                story.append(Paragraph("User Guide — Text-command 3D modelling with Open CASCADE, for Mac and iPad", S["subtitle"]))
                story.append(Spacer(1, 6))
                title_done = True
            else:
                story.append(PageBreak())
                story.append(Paragraph(inline(text), S["h1"]))
        elif level == 2:
            if not first_h1:
                pass
            story.append(Paragraph(inline(text), S["h2"]))
        else:
            story.append(Paragraph(inline(text), S["h3"]))
        i += 1
        continue
    if ln.strip() == "---":
        story.append(Spacer(1, 4)); i += 1; continue
    if not ln.strip():
        i += 1; continue
    if ln.strip().startswith(">"):
        buf = []
        while i < len(lines) and lines[i].strip().startswith(">"):
            buf.append(lines[i].strip().lstrip(">").strip()); i += 1
        story.append(Paragraph(inline(" ".join(buf)), S["quote"]))
        continue
    if re.match(r"^\s*-\s+", ln):
        buf = [re.sub(r"^\s*-\s+", "", ln)]
        i += 1
        while i < len(lines) and lines[i].strip() and not re.match(r"^\s*(-\s+|#{1,3}\s|\||>|```|\d+\.\s)", lines[i]) and lines[i].startswith("  "):
            buf.append(lines[i].strip()); i += 1
        story.append(Paragraph(inline(" ".join(buf)), S["bullet"], bulletText="•"))
        continue
    m = re.match(r"^\s*(\d+)\.\s+(.*)$", ln)
    if m:
        buf = [m.group(2)]
        i += 1
        while i < len(lines) and lines[i].strip() and lines[i].startswith("  ") and not re.match(r"^\s*\d+\.\s", lines[i]):
            buf.append(lines[i].strip()); i += 1
        story.append(Paragraph(inline(" ".join(buf)), S["num"], bulletText=m.group(1) + "."))
        continue
    # plain paragraph: gather wrapped lines
    buf = [ln.strip()]
    i += 1
    while i < len(lines) and lines[i].strip() and not re.match(r"^\s*(#{1,3}\s|-\s|\||>|```|\d+\.\s)", lines[i]) and lines[i].strip() != "---":
        buf.append(lines[i].strip()); i += 1
    story.append(Paragraph(inline(" ".join(buf)), S["body"]))

def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 9)
    canvas.setFillColor(colors.HexColor("#444444"))
    canvas.drawString(0.75 * inch, 0.55 * inch, "Cascade Console — User Guide v1.0")
    canvas.drawRightString(LETTER[0] - 0.75 * inch, 0.55 * inch, f"Page {doc.page}")
    canvas.setStrokeColor(RULE); canvas.setLineWidth(0.7)
    canvas.line(0.75 * inch, 0.72 * inch, LETTER[0] - 0.75 * inch, 0.72 * inch)
    canvas.restoreState()

doc = BaseDocTemplate(OUT, pagesize=LETTER, leftMargin=0.75 * inch, rightMargin=0.75 * inch,
                      topMargin=0.7 * inch, bottomMargin=0.9 * inch,
                      title="Cascade Console — User Guide", author="user")
frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="main")
doc.addPageTemplates([PageTemplate(id="page", frames=[frame], onPage=footer)])
doc.build(story)
print("built", OUT)
