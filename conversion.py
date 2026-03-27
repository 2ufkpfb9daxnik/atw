import re

INPUT_FILE_PATH = "src/odai/default.txt"  # 読み込むお題ファイルのパス
OUTPUT_FILE_PATH = "data.js"     # 書き出すJavaScriptファイルのパス

def convert_typing_data():
    try:
        # 1. 入力ファイルを読み込む
        with open(INPUT_FILE_PATH, "r", encoding="utf-8") as f:
            lines = f.readlines()
        
        cleaned_lines = []
        for line in lines:
            line = line.strip()
            if not line:
                continue # 空行は無視する
            
            # 正規表現で [漢字](ふりがな) の部分を「漢字」だけにする
            # \[ (.*?) \]  -> 角カッコの中身（漢字）をグループ1として取得
            # \( (.*?) \)  -> 丸カッコの中身（ふりがな）は無視
            # \1 でグループ1（漢字）に置き換え
            clean_line = re.sub(r'\[(.*?)\]\((.*?)\)', r'\1', line)
            cleaned_lines.append(clean_line)

        # 2. JavaScriptの配列形式に整形
        js_output = "const candidates = [\n"
        for i, text in enumerate(cleaned_lines):
            # 万が一、お題の中にダブルクォーテーションがあった場合に壊れないようエスケープ処理
            escaped_text = text.replace('"', '\\"')
            
            # 最後の行だけカンマをつけない
            if i == len(cleaned_lines) - 1:
                js_output += f'    "{escaped_text}"\n'
            else:
                js_output += f'    "{escaped_text}",\n'
        js_output += "];\n"

        # 3. 出力ファイルに書き込む（上書き）
        with open(OUTPUT_FILE_PATH, "w", encoding="utf-8") as f:
            f.write(js_output)
            
        print(f"成功！ {len(cleaned_lines)} 件のお題を {OUTPUT_FILE_PATH} に書き出しました。")

    except FileNotFoundError:
        print(f"エラー: '{INPUT_FILE_PATH}' が見つかりません。同じフォルダにファイルがあるか確認してください。")
    except Exception as e:
        print(f"エラーが発生しました: {e}")

if __name__ == "__main__":
    convert_typing_data()