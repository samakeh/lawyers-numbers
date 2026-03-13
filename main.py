import sqlite3
import tkinter as tk
from tkinter import ttk
import ttkbootstrap as tb
from ttkbootstrap.constants import *
from ttkbootstrap.scrolled import ScrolledFrame
import os
import sys

class LawyerApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Lawyers Book - دليل المحامين")
        self.root.geometry("1100x750")
        
        # Initialize style object once
        self.style = tb.Style(theme="flatly")
        
        self.setup_db()
        self.create_widgets()
        self.load_data()

    def setup_db(self):
        # Database path handling for PyInstaller
        base_path = getattr(sys, '_MEIPASS', os.path.abspath("."))
        db_path = os.path.join(base_path, "lawyers.db")
        
        # If not in MEIPASS, check current directory
        if not os.path.exists(db_path):
            db_path = "lawyers.db"
            
        print(f"Connecting to database at: {db_path}")
        self.conn = sqlite3.connect(db_path)
        self.cursor = self.conn.cursor()

    def create_widgets(self):
        # Main Layout
        self.main_container = ttk.Frame(self.root)
        self.main_container.pack(fill=BOTH, expand=YES, padx=10, pady=10)

        # Header
        header_frame = ttk.Frame(self.main_container, style='primary.TFrame')
        header_frame.pack(fill=X, pady=(0, 10))
        
        # Add Lawyer Button (Left side of header)
        self.add_btn = ttk.Button(
            header_frame, 
            text=" إضافة محامي جديد +", 
            style='success.TButton',
            command=self.show_add_dialog
        )
        self.add_btn.pack(side=LEFT, padx=15, pady=15)

        header_label = ttk.Label(
            header_frame, 
            text="Lawyers Book - دليل المحامين", 
            font=("Segoe UI", 24, "bold"),
            style='inverse-primary.TLabel'
        )
        header_label.pack(side=RIGHT, padx=20, pady=15)

        # Search Area
        search_frame = ttk.Frame(self.main_container)
        search_frame.pack(fill=X, pady=10)

        ttk.Label(search_frame, text="بحث بالاسم أو المدينة:").pack(side=RIGHT, padx=5)
        self.search_var = tk.StringVar()
        self.search_var.trace("w", self.on_search_change)
        
        self.search_entry = ttk.Entry(
            search_frame, 
            textvariable=self.search_var, 
            font=("Segoe UI", 12),
            justify=RIGHT
        )
        self.search_entry.pack(side=RIGHT, fill=X, expand=YES, padx=5)
        self.search_entry.focus_set()

        # Two Columns Layout
        content_frame = ttk.Frame(self.main_container)
        content_frame.pack(fill=BOTH, expand=YES)

        # Details Panel (Sidebar - Left)
        self.details_frame = ttk.LabelFrame(
            content_frame, 
            text="تفاصيل المحامي", 
            padding=20, 
            style='primary.TLabelframe'
        )
        self.details_frame.pack(side=LEFT, fill=BOTH, expand=NO)
        
        self.details_scroll = ScrolledFrame(self.details_frame, autohide=True, width=380)
        self.details_scroll.pack(fill=BOTH, expand=YES)

        self.info_labels = {}
        fields = [
            ("Name", "الاسم الكامل:"),
            ("Membership", "رقم العضوية:"),
            ("City", "المدينة:"),
            ("Phone", "رقم الجوال:"),
            ("Telephone", "رقم الهاتف:"),
            ("Fax", "الفاكس:"),
            ("Email", "البريد الإلكتروني:"),
            ("Address", "العنوان:"),
        ]

        for key, text in fields:
            f = ttk.Frame(self.details_scroll)
            f.pack(fill=X, pady=5)
            # Label for the field name
            ttk.Label(f, text=text, font=("Segoe UI", 10, "bold"), style='secondary.TLabel').pack(side=RIGHT)
            
            # Entry instead of Label for copy-paste support
            val_var = tk.StringVar()
            val_entry = ttk.Entry(
                f, 
                textvariable=val_var, 
                font=("Segoe UI", 11), 
                justify=RIGHT,
                state='readonly',
                style='primary.TEntry' # Standard entry style
            )
            # Remove border to make it look cleaner like a label but selectable
            val_entry.config(exportselection=True) 
            val_entry.pack(side=RIGHT, padx=10, fill=X, expand=YES)
            
            self.info_labels[key] = (val_var, val_entry)

        # Results List (Treeview - Right)
        list_frame = ttk.Frame(content_frame)
        list_frame.pack(side=RIGHT, fill=BOTH, expand=YES, padx=(10, 0))

        columns = ("ID", "Membership", "City", "Name")
        self.tree = ttk.Treeview(
            list_frame, 
            columns=columns, 
            show="headings",
            style='info.Treeview'
        )
        
        self.tree.heading("ID", text="ID")
        self.tree.heading("Membership", text="رقم العضوية")
        self.tree.heading("City", text="المدينة")
        self.tree.heading("Name", text="الاسم الكامل")

        self.tree.column("ID", width=50, anchor=CENTER)
        self.tree.column("Membership", width=100, anchor=CENTER)
        self.tree.column("City", width=100, anchor=E)
        self.tree.column("Name", width=300, anchor=E)

        self.tree.pack(side=RIGHT, fill=BOTH, expand=YES)
        
        scrollbar = ttk.Scrollbar(list_frame, orient=VERTICAL, command=self.tree.yview)
        self.tree.configure(yscrollcommand=scrollbar.set)
        scrollbar.pack(side=RIGHT, fill=Y)

        self.tree.bind("<<TreeviewSelect>>", self.on_tree_select)
        
        # Set Window Icon
        self.set_app_icon()

    def set_app_icon(self):
        icon_path = os.path.join(getattr(sys, '_MEIPASS', os.path.abspath(".")), "app_icon.png")
        if not os.path.exists(icon_path):
            icon_path = "app_icon.png"
            
        if os.path.exists(icon_path):
            try:
                from PIL import Image, ImageTk
                img = Image.open(icon_path)
                photo = ImageTk.PhotoImage(img)
                self.root.iconphoto(True, photo)
                # Keep reference to avoid garbage collection
                self._icon_photo = photo
            except Exception as e:
                print(f"Failed to set icon: {e}")

    def show_add_dialog(self):
        dialog = AddLawyerDialog(self.root, self.save_lawyer)
        self.root.wait_window(dialog.top)

    def save_lawyer(self, data):
        try:
            sql = """
                INSERT INTO lawyers (FullName, ArFullName, Membership, City, ArCity, Phone, Telephone, Fax, Email, ArAddress, Address)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            self.cursor.execute(sql, (
                data['FullName'], data['FullName'], data['Membership'], 
                data['City'], data['City'], data['Phone'], 
                data['Telephone'], data['Fax'], data['Email'],
                data['Address'], data['Address']
            ))
            self.conn.commit()
            self.load_data() # Refresh list
            return True
        except Exception as e:
            print(f"Error saving: {e}")
            return False

    def load_data(self, query=None):
        for item in self.tree.get_children():
            self.tree.delete(item)

        try:
            if not query:
                sql = "SELECT ID, Membership, City, FullName FROM lawyers ORDER BY ID DESC LIMIT 100"
                self.cursor.execute(sql)
            else:
                sql = """
                    SELECT ID, Membership, City, FullName FROM lawyers 
                    WHERE FullName LIKE ? OR ArFullName LIKE ? OR City LIKE ? OR ArCity LIKE ? OR Membership LIKE ?
                    ORDER BY ID DESC LIMIT 100
                """
                like_q = f"%{query}%"
                self.cursor.execute(sql, (like_q, like_q, like_q, like_q, like_q))

            for row in self.cursor.fetchall():
                self.tree.insert("", END, values=row)
        except Exception as e:
            print(f"Database error: {e}")

    def on_search_change(self, *args):
        query = self.search_var.get()
        self.load_data(query)

    def on_tree_select(self, event):
        selected = self.tree.selection()
        if not selected:
            return
        
        item = self.tree.item(selected[0])
        lawyer_id = item['values'][0]
        
        self.cursor.execute("SELECT * FROM lawyers WHERE ID = ?", (lawyer_id,))
        row = self.cursor.fetchone()
        
        if row:
            cols = [desc[0] for desc in self.cursor.description]
            data = dict(zip(cols, row))
            
            # Map data keys to info_labels keys
            mapping = {
                "Name": "ArFullName",
                "Membership": "Membership",
                "City": "ArCity",
                "Phone": "Phone",
                "Telephone": "Telephone",
                "Fax": "Fax",
                "Email": "Email",
                "Address": "ArAddress"
            }
            
            for key, db_col in mapping.items():
                val_var, val_entry = self.info_labels[key]
                val_var.set(str(data.get(db_col, data.get(key.replace("Ar", ""), ""))))

class AddLawyerDialog:
    def __init__(self, parent, save_callback):
        self.top = tb.Toplevel(parent)
        self.top.title("إضافة محامي جديد")
        self.top.geometry("500x650")
        self.top.grab_set() # Modal
        self.save_callback = save_callback
        
        self.entries = {}
        self.create_widgets()

    def create_widgets(self):
        container = ttk.Frame(self.top, padding=20)
        container.pack(fill=BOTH, expand=YES)

        fields = [
            ("FullName", "الاسم الكامل:"),
            ("Membership", "رقم العضوية:"),
            ("City", "المدينة:"),
            ("Phone", "رقم الجوال:"),
            ("Telephone", "رقم الهاتف:"),
            ("Fax", "الفاكس:"),
            ("Email", "البريد الإلكتروني:"),
            ("Address", "العنوان (بالكامل):"),
        ]

        for key, label_text in fields:
            f = ttk.Frame(container)
            f.pack(fill=X, pady=5)
            ttk.Label(f, text=label_text, font=("Segoe UI", 10)).pack(side=RIGHT)
            entry = ttk.Entry(f, justify=RIGHT, font=("Segoe UI", 10))
            entry.pack(side=RIGHT, fill=X, expand=YES, padx=(0, 10))
            self.entries[key] = entry

        btn_frame = ttk.Frame(container)
        btn_frame.pack(fill=X, pady=20)

        save_btn = ttk.Button(btn_frame, text="حفظ", style='success.TButton', command=self.on_save)
        save_btn.pack(side=RIGHT, padx=5)
        
        cancel_btn = ttk.Button(btn_frame, text="إلغاء", style='danger.TButton', command=self.top.destroy)
        cancel_btn.pack(side=RIGHT, padx=5)

    def on_save(self):
        data = {key: entry.get().strip() for key, entry in self.entries.items()}
        
        if not data['FullName'] or not data['Membership']:
            from tkinter import messagebox
            messagebox.showwarning("تنبيه", "يرجى إدخال الاسم الكامل ورقم العضوية على الأقل.")
            return

        if self.save_callback(data):
            self.top.destroy()
        else:
            from tkinter import messagebox
            messagebox.showerror("خطأ", "فشل حفظ البيانات.")

if __name__ == "__main__":
    # Create the window without passing themename directly, or use tb.Window
    # Using tb.Window but avoiding the redundant Style in __init__ if it causes issues.
    # Actually, the best way for EXE is:
    root = tb.Window(themename="flatly")
    app = LawyerApp(root)
    root.mainloop()
