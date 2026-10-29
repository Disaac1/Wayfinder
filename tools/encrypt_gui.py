#!/usr/bin/env python3
"""
Wayfinder Game File Encryptor / Decryptor GUI
Graphical wrapper around encrypt_game_file.py (Godot AES-256 compatible).
"""

import sys
import os
import threading
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

# Import core encryption logic
try:
    from encrypt_game_file import encrypt_file, decrypt_file
except ImportError:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, script_dir)
    from encrypt_game_file import encrypt_file, decrypt_file


class EncryptorGUI(tk.Tk):
    def __init__(self):
        super().__init__()

        self.title("Wayfinder - Game File Encryptor (.enc)")
        self.geometry("640x380")
        self.minsize(580, 360)

        # Apply basic styling
        self.style = ttk.Style(self)
        if "clam" in self.style.theme_names():
            self.style.theme_use("clam")

        self.mode_var = tk.StringVar(value="encrypt")
        self.input_path_var = tk.StringVar()
        self.output_path_var = tk.StringVar()
        self.key_var = tk.StringVar()
        self.status_var = tk.StringVar(value="Ready")
        self.show_key_var = tk.BooleanVar(value=False)

        self._build_ui()

    def _build_ui(self):
        container = ttk.Frame(self, padding=16)
        container.pack(fill=tk.BOTH, expand=True)

        # Mode selection
        mode_frame = ttk.LabelFrame(container, text=" Mode ", padding=10)
        mode_frame.pack(fill=tk.X, pady=(0, 10))

        rb_enc = ttk.Radiobutton(
            mode_frame,
            text="Encrypt (File -> .enc)",
            value="encrypt",
            variable=self.mode_var,
            command=self._on_mode_change
        )
        rb_enc.pack(side=tk.LEFT, padx=(0, 20))

        rb_dec = ttk.Radiobutton(
            mode_frame,
            text="Decrypt (.enc -> File)",
            value="decrypt",
            variable=self.mode_var,
            command=self._on_mode_change
        )
        rb_dec.pack(side=tk.LEFT)

        # File selections
        files_frame = ttk.LabelFrame(container, text=" Files ", padding=10)
        files_frame.pack(fill=tk.X, pady=(0, 10))
        files_frame.columnconfigure(1, weight=1)

        # Input
        ttk.Label(files_frame, text="Input File:").grid(row=0, column=0, sticky=tk.W, pady=4)
        in_entry = ttk.Entry(files_frame, textvariable=self.input_path_var)
        in_entry.grid(row=0, column=1, sticky=tk.EW, padx=8, pady=4)
        ttk.Button(files_frame, text="Browse...", command=self._browse_input).grid(row=0, column=2, pady=4)

        # Output
        ttk.Label(files_frame, text="Output File:").grid(row=1, column=0, sticky=tk.W, pady=4)
        out_entry = ttk.Entry(files_frame, textvariable=self.output_path_var)
        out_entry.grid(row=1, column=1, sticky=tk.EW, padx=8, pady=4)
        ttk.Button(files_frame, text="Browse...", command=self._browse_output).grid(row=1, column=2, pady=4)

        # Passphrase
        key_frame = ttk.LabelFrame(container, text=" Encryption Key / Passphrase ", padding=10)
        key_frame.pack(fill=tk.X, pady=(0, 12))
        key_frame.columnconfigure(0, weight=1)

        self.key_entry = ttk.Entry(key_frame, textvariable=self.key_var, show="*")
        self.key_entry.grid(row=0, column=0, sticky=tk.EW, padx=(0, 8))

        chk_show = ttk.Checkbutton(
            key_frame,
            text="Show Passphrase",
            variable=self.show_key_var,
            command=self._toggle_show_key
        )
        chk_show.grid(row=0, column=1)

        # Action Button & Progress
        self.btn_run = ttk.Button(container, text="Start Encryption", command=self._start_process)
        self.btn_run.pack(fill=tk.X, ipady=6, pady=(0, 10))

        # Status Bar
        status_frame = ttk.Frame(container)
        status_frame.pack(fill=tk.X)
        
        self.lbl_status = ttk.Label(status_frame, textvariable=self.status_var, relief=tk.SUNKEN, anchor=tk.W, padding=4)
        self.lbl_status.pack(fill=tk.X)

    def _toggle_show_key(self):
        if self.show_key_var.get():
            self.key_entry.config(show="")
        else:
            self.key_entry.config(show="*")

    def _on_mode_change(self):
        mode = self.mode_var.get()
        if mode == "encrypt":
            self.btn_run.config(text="Start Encryption")
        else:
            self.btn_run.config(text="Start Decryption")
        self._update_default_output()

    def _update_default_output(self):
        in_path = self.input_path_var.get().strip()
        if not in_path:
            return

        mode = self.mode_var.get()
        if mode == "encrypt":
            if not in_path.endswith(".enc"):
                self.output_path_var.set(f"{in_path}.enc")
            else:
                self.output_path_var.set(f"{in_path}.reenc")
        else:
            if in_path.endswith(".enc"):
                self.output_path_var.set(in_path[:-4])
            else:
                self.output_path_var.set(f"{in_path}.dec")

    def _browse_input(self):
        path = filedialog.askopenfilename(
            title="Select File",
            filetypes=[("All Files", "*.*"), ("Encrypted Files (*.enc)", "*.enc")]
        )
        if path:
            self.input_path_var.set(path)
            # Auto-detect mode based on file extension if user hasn't explicitly set output
            if path.lower().endswith(".enc"):
                self.mode_var.set("decrypt")
                self.btn_run.config(text="Start Decryption")
            else:
                self.mode_var.set("encrypt")
                self.btn_run.config(text="Start Encryption")
            self._update_default_output()

    def _browse_output(self):
        mode = self.mode_var.get()
        if mode == "encrypt":
            path = filedialog.asksaveasfilename(
                title="Select Encrypted Output File",
                defaultextension=".enc",
                filetypes=[("Encrypted Files (*.enc)", "*.enc"), ("All Files", "*.*")]
            )
        else:
            path = filedialog.asksaveasfilename(
                title="Select Decrypted Output Destination",
                filetypes=[("All Files", "*.*")]
            )
        if path:
            self.output_path_var.set(path)

    def _set_ui_state(self, running: bool):
        state = tk.DISABLED if running else tk.NORMAL
        self.btn_run.config(state=state)

    def _start_process(self):
        in_path = self.input_path_var.get().strip()
        out_path = self.output_path_var.get().strip()
        key = self.key_var.get()
        mode = self.mode_var.get()

        if not in_path or not os.path.exists(in_path):
            messagebox.showerror("Error", "Please select a valid input file.")
            return

        if not out_path:
            messagebox.showerror("Error", "Please specify an output file path.")
            return

        if not key:
            messagebox.showerror("Error", "Please provide a passphrase/key.")
            return

        self._set_ui_state(True)
        self.status_var.set(f"Processing ({mode})... Please wait.")

        def run_worker():
            try:
                if mode == "encrypt":
                    encrypt_file(in_path, out_path, key)
                    msg = f"Encryption complete!\nSaved to: {out_path}"
                else:
                    decrypt_file(in_path, out_path, key)
                    msg = f"Decryption complete!\nSaved to: {out_path}"

                self.after(0, lambda: self._on_success(msg))
            except Exception as e:
                err_msg = str(e)
                self.after(0, lambda: self._on_failure(err_msg))

        threading.Thread(target=run_worker, daemon=True).start()

    def _on_success(self, msg):
        self._set_ui_state(False)
        self.status_var.set("Ready - Last operation succeeded.")
        messagebox.showinfo("Success", msg)

    def _on_failure(self, err):
        self._set_ui_state(False)
        self.status_var.set("Error occurred.")
        messagebox.showerror("Operation Failed", f"Error: {err}")


def main():
    app = EncryptorGUI()
    app.mainloop()


if __name__ == "__main__":
    main()
