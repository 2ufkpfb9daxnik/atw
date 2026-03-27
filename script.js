// --- 縦ストリームの生成 ---
function generateVerticalText() {
    let html = "";
    for (let i = 0; i < 400; i++) {
        const randomIndex = Math.floor(Math.random() * candidates.length);
        html += candidates[randomIndex]; 
    }
    return html;
}

// --- 横ストリームの生成 ---
function generateHorizontalText() {
    let html = "";
    for (let i = 0; i < 20; i++) {
        let lineText = "";
        for (let j = 0; j < 25; j++) {
            const randomIndex = Math.floor(Math.random() * candidates.length);
            lineText += candidates[randomIndex]; 
        }
        html += lineText + "<br>";
    }
    return html;
}

const verticalHTML = generateVerticalText();
document.getElementById('bgTextElementVert1').innerHTML = verticalHTML;
document.getElementById('bgTextElementVert2').innerHTML = verticalHTML;

const horizontalHTML = generateHorizontalText();
document.getElementById('bgTextElementHoriz1').innerHTML = horizontalHTML;
document.getElementById('bgTextElementHoriz2').innerHTML = horizontalHTML;