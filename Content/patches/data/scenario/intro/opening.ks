
*opening
[cm][chara_config ptext="chara_name_area" pos_mode="false" time="600" anim="true" effect="" ]
[call storage="pre/exp.ks" target="*first" ]
[chara_mod name="black" wait="false" time="0" storage="00.png" ]
[chara_show name="black" layer=1 time="0" wait="true" left="-1" zindex=500 ]
[bg_door][show_message_w][bgm_IF]
[chara_anim][chara_config pos_mode="true" anim="true" ]

[_]……[p]
[button target="*xl_1" graphic="ch/1.png" x="0" y="0" ][s]

*xl_1
[cm]
[_]……[p]
[button target="*xl_2" graphic="ch/2.png" x="0" y="0" ][s]

*xl_2
[cm]
[_]……[p]
[button target="*xl_3" graphic="ch/3.png" x="0" y="0" ][s]

*xl_3
[cm]
[_]……[p]
[button target="*xl_4" graphic="ch/6.png" x="0" y="0" ][s]

*xl_4
[cm]
[_]……[p]
[button target="*xl_5" graphic="ch/5.png" x="0" y="0" ][s]

*xl_5
[cm]
[_]（今天太陽剛剛升起來的時候。[lr]
我聽到了沉稳的敲門聲。[p]
（今天並沒有邀請誰的預定[r]
我也沒有能夠不打招呼就前來拜訪的熟人。[p]
會是什麼人呢？[p]
[chara_mod name="sub" time="1" storage="o/sub/def.png" ]
[chara_show name="sub" time="100" wait="true" ]
#怪異的男人
[chara_mod name="sub" time="100" storage="o/sub/smile.png" ]

你好醫生。[p]
[_]（打開門見到一個形跡可疑的的中年男人站在家門前。[p]
#怪異的男人
你還記得我嗎？[lr]
我曾經被醫生你救過一命。[p]
[_]（…我把男人的臉和記憶進行對照。[lr]
瞬間察覺到這次的遊戲應該是MOD版……[p]

#怪異的男人
沒錯、上次我被海軍抓起來的時候就是你徒手殲滅700萬海軍才救了我。[lr]
最後離別前還送了一頂漂亮的帽子給我、[lr]
所以這次我也不多說了進入正題吧。[p]

#怪異的男人
希望大家能進剛才的頁面支持繪畫創作一下。[p]
如果找不到我們的話可進愛發電或者公眾號REBEL-POWER。[p]
順帶一提我們還有插畫收集群。[lr]
裡面收集了大約1TB的插畫、開場動畫裡用的插畫就是用它們做的。[p]

#怪異的男人
現在給你女主角讓你開始遊戲吧。[p]

[chara_mod name="body" time="1" storage="s/body/stand.png" ]
[chara_show name="body" time="100" wait="true" ]
#怪異的男人
這次的遊戲設定為可以隨便性交。[lr]
但是要接收她要先完成一系列任務…。[lr]
否則你就沒有資格可以收留她。[p]
那麼現在…。[lr]
開始吧！。[p]


[jump target="*y20"]

*no
[cm]
#怪異的男人
我等你。[p]
要開始了嗎？[p]



[button target="*no" graphic="ch/zdd.png" x="0" y="350" ]
[button target="*ok" graphic="ch/ksrw.png" x="0" y="200" ][s]

*ok
[cm]
#怪異的男人
下面的問題要全部回答正確就可以過關然後接收你老婆了。[p]
首先。[lr]
凌波麗出場在EVA的第幾集？[p]

[button target="*sb1x" graphic="ch/q1.png" x="0" y="350" ]
[button target="*cg1x" graphic="ch/q2.png" x="0" y="200" ][s]

*cg1x
[cm]
#怪異的男人
雙殻剛動物身體那一部分屬於身體前端？[p]

[button target="*y1" graphic="ch/w1.png" x="0" y="350" ]
[button target="*n1" graphic="ch/w2.png" x="0" y="200" ][s]

*sb1x
[cm]
#怪異的男人
雙殻剛動物身體那一部分屬於身體前端？[p]

[button target="*n1" graphic="ch/w1.png" x="0" y="350" ]
[button target="*n1" graphic="ch/w2.png" x="0" y="200" ][s]

*n1
[cm]
#怪異的男人
現存兩棲動物有幾個目？[p]

[button target="*n2" graphic="ch/e1.png" x="0" y="350" ]
[button target="*n2" graphic="ch/e2.png" x="0" y="200" ][s]


*y1
[cm]
#怪異的男人
現存兩棲動物有幾個目？[p]

[button target="*y2" graphic="ch/e1.png" x="0" y="350" ]
[button target="*n2" graphic="ch/e2.png" x="0" y="200" ][s]

*n2
[cm]
#怪異的男人
超人武士賽博小隊中幫助魔王Kilokahn製作病毒的人叫什麼？[p]

[button target="*nx" graphic="ch/u1.png" x="0" y="350" ]
[button target="*nx" graphic="ch/u2.png" x="0" y="200" ][s]

*y2
[cm]
#怪異的男人
超人武士賽博小隊中幫助魔王Kilokahn製作病毒的人叫什麼？[p]

[button target="*nx" graphic="ch/u1.png" x="0" y="350" ]
[button target="*yx" graphic="ch/u2.png" x="0" y="200" ][s]


*nx
[cm]
#怪異的男人
施洗約翰和耶穌是什麼關係？[p]

[button target="*n3" graphic="ch/30.png" x="0" y="350" ]
[button target="*n3" graphic="ch/31.png" x="0" y="200" ][s]

*yx
[cm]
#怪異的男人
施洗約翰和耶穌是什麼關係？[p]

[button target="*y3" graphic="ch/30.png" x="0" y="350" ]
[button target="*n3" graphic="ch/31.png" x="0" y="200" ][s]

*n3
[cm]
#怪異的男人
737-800應該讀作什麼？[p]

[button target="*n4" graphic="ch/r6.png" x="0" y="350" ]
[button target="*n4" graphic="ch/r7.png" x="0" y="200" ][s]

*y3
[cm]
#怪異的男人
737-800應該讀作什麼？[p]

[button target="*y4" graphic="ch/r6.png" x="0" y="350" ]
[button target="*n4" graphic="ch/r7.png" x="0" y="200" ][s]

*n4
[cm]
#怪異的男人
蛇頸龍和長頸龍頸椎的區別是什麼？[p]

[button target="*n5" graphic="ch/t4.png" x="0" y="350" ]
[button target="*n5" graphic="ch/t5.png" x="0" y="200" ][s]

*y4
[cm]
#怪異的男人
蛇頸龍和長頸龍頸椎的區別是什麼？[p]

[button target="*n5" graphic="ch/t4.png" x="0" y="350" ]
[button target="*y5" graphic="ch/t5.png" x="0" y="200" ][s]


*n5
[cm]
#怪異的男人
鱟在分類學上屬於節肢動物的什麼剛？[p]

[button target="*n6" graphic="ch/o7.png" x="0" y="350" ]
[button target="*n6" graphic="ch/o3.png" x="0" y="200" ][s]

*y5
[cm]
#怪異的男人
鱟在分類學上屬於節肢動物的什麼剛？[p]

[button target="*n6" graphic="ch/o7.png" x="0" y="350" ]
[button target="*y6" graphic="ch/o3.png" x="0" y="200" ][s]

*n6
[cm]
#怪異的男人
為什麼宇宙中沒有黑矮星？[p]

[button target="*n7" graphic="ch/14.png" x="0" y="350" ]
[button target="*n7" graphic="ch/15.png" x="0" y="200" ][s]

*y6
[cm]
#怪異的男人
為什麼宇宙中沒有黑矮星？[p]

[button target="*y7" graphic="ch/14.png" x="0" y="350" ]
[button target="*n7" graphic="ch/15.png" x="0" y="200" ][s]


*n7
[cm]
#怪異的男人
鈴子的超能力是什麼？[p]

[button target="*n8" graphic="ch/16.png" x="0" y="350" ]
[button target="*n8" graphic="ch/17.png" x="0" y="200" ][s]

*y7
[cm]
#怪異的男人
鈴子的超能力是什麼？[p]

[button target="*y8" graphic="ch/16.png" x="0" y="350" ]
[button target="*n8" graphic="ch/17.png" x="0" y="200" ][s]



*n8
[cm]
#怪異的男人
可否用已知宇宙的能量製作一純淨水瓶的純電子？[p]

[button target="*n10" graphic="ch/18.png" x="0" y="350" ]
[button target="*n10" graphic="ch/19.png" x="0" y="200" ][s]

*y8
[cm]
#怪異的男人
可否用已知宇宙的能量製作一純淨水瓶的純電子？[p]

[button target="*y10" graphic="ch/18.png" x="0" y="350" ]
[button target="*n10" graphic="ch/19.png" x="0" y="200" ][s]

*n10
[cm]
#怪異的男人
官方給出的兩津勘吉負債總額是多少？[p]

[button target="*n11" graphic="ch/a1.png" x="0" y="350" ]
[button target="*n11" graphic="ch/a2.png" x="0" y="200" ][s]

*y10
[cm]
#怪異的男人
官方給出的兩津勘吉負債總額是多少？[p]

[button target="*n11" graphic="ch/a1.png" x="0" y="350" ]
[button target="*y11" graphic="ch/a2.png" x="0" y="200" ][s]



*n11
[cm]
#怪異的男人
為什麼油畫在繪畫背景暗部的情況下一般不能使用含藍的紅色？[p]

[button target="*n00" graphic="ch/24.png" x="0" y="350" ]
[button target="*n00" graphic="ch/25.png" x="0" y="200" ][s]

*y11
[cm]
#怪異的男人
為什麼油畫在繪畫背景暗部的情況下一般不能使用含藍的紅色？[p]

[button target="*y00" graphic="ch/24.png" x="0" y="350" ]
[button target="*n00" graphic="ch/25.png" x="0" y="200" ][s]


*n00
[cm]
#怪異的男人
蓋亞能量炮中的蓋亞是什麼？[p]

[button target="*n12" graphic="ch/33.png" x="0" y="350" ]
[button target="*n12" graphic="ch/32.png" x="0" y="200" ][s]

*y00
[cm]
#怪異的男人
蓋亞能量炮中的蓋亞是什麼？[p]

[button target="*n12" graphic="ch/33.png" x="0" y="350" ]
[button target="*y12" graphic="ch/32.png" x="0" y="200" ][s]

*n12
[cm]
#怪異的男人
摩西是在什麼山上面見上帝的？[p]

[button target="*n13" graphic="ch/26.png" x="0" y="350" ]
[button target="*n13" graphic="ch/27.png" x="0" y="200" ][s]


*y12
[cm]
#怪異的男人
摩西是在什麼山上面見上帝的？[p]

[button target="*y13" graphic="ch/26.png" x="0" y="350" ]
[button target="*n13" graphic="ch/27.png" x="0" y="200" ][s]



*n13
[cm]
#怪異的男人
地球壓縮成中子態後有多大？[p]

[button target="*n77" graphic="ch/42.png" x="0" y="350" ]
[button target="*n77" graphic="ch/43.png" x="0" y="200" ][s]


*y13
[cm]
#怪異的男人
地球壓縮成中子態後有多大？[p]

[button target="*y77" graphic="ch/42.png" x="0" y="350" ]
[button target="*n77" graphic="ch/43.png" x="0" y="200" ][s]

*n77
[cm]
#怪異的男人
玄鐵是什麼東西？[p]

[button target="*n14" graphic="ch/35.png" x="0" y="350" ]
[button target="*n14" graphic="ch/34.png" x="0" y="200" ][s]

*y77
[cm]
#怪異的男人
玄鐵是什麼東西？[p]

[button target="*n14" graphic="ch/35.png" x="0" y="350" ]
[button target="*y14" graphic="ch/34.png" x="0" y="200" ][s]


*n14
[cm]
#怪異的男人
為什麼阿拉蕾中的酸梅超人要說吃顆酸梅變超人？[p]

[button target="*n15" graphic="ch/28.png" x="0" y="350" ]
[button target="*n15" graphic="ch/29.png" x="0" y="200" ][s]


*y14
[cm]
#怪異的男人
為什麼阿拉蕾中的酸梅超人要說吃顆酸梅變超人？[p]

[button target="*y15" graphic="ch/28.png" x="0" y="350" ]
[button target="*n15" graphic="ch/29.png" x="0" y="200" ][s]



*n15
[cm]
#怪異的男人
渡渡鳥是什麼？[p]

[button target="*n1c" graphic="ch/37.png" x="0" y="350" ]
[button target="*n1c" graphic="ch/36.png" x="0" y="200" ][s]


*y15
[cm]
#怪異的男人
渡渡鳥是什麼？[p]

[button target="*n1c" graphic="ch/37.png" x="0" y="350" ]
[button target="*y1c" graphic="ch/36.png" x="0" y="200" ][s]


*n1c
[cm]
#怪異的男人
莉娜因巴斯最喜歡用的大招是什麼？[p]

[button target="*n16" graphic="ch/40.png" x="0" y="350" ]
[button target="*n16" graphic="ch/41.png" x="0" y="200" ][s]

*y1c
[cm]
#怪異的男人
莉娜因巴斯最喜歡用的大招是什麼？[p]

[button target="*y16" graphic="ch/40.png" x="0" y="350" ]
[button target="*n16" graphic="ch/41.png" x="0" y="200" ][s]

*n16
[cm]
#怪異的男人
脊索動物門和那個動物們關係比較近？[p]

[button target="*n17" graphic="ch/c1.png" x="0" y="350" ]
[button target="*n17" graphic="ch/c0.png" x="0" y="200" ][s]


*y16
[cm]
#怪異的男人
脊索動物門和那個動物們關係比較近？[p]

[button target="*n17" graphic="ch/c1.png" x="0" y="350" ]
[button target="*y17" graphic="ch/c0.png" x="0" y="200" ][s]

*n17
[cm]
#怪異的男人
同等條件下亞洲人與歐洲人畫油畫的最大區別是什麼？[p]

[button target="*n18" graphic="ch/45.png" x="0" y="350" ]
[button target="*n18" graphic="ch/44.png" x="0" y="200" ][s]

*y17
[cm]
#怪異的男人
同等條件下亞洲人與歐洲人畫油畫的最大區別是什麼？[p]

[button target="*n18" graphic="ch/45.png" x="0" y="350" ]
[button target="*y18" graphic="ch/44.png" x="0" y="200" ][s]

*n18
[cm]
#怪異的男人
製作德國基佬香腸的重要條件是什麼？[p]

[button target="*n19" graphic="ch/46.png" x="0" y="350" ]
[button target="*n19" graphic="ch/47.png" x="0" y="200" ][s]


*y18
[cm]
#怪異的男人
製作德國基佬香腸的重要條件是什麼？[p]

[button target="*y19" graphic="ch/46.png" x="0" y="350" ]
[button target="*n19" graphic="ch/47.png" x="0" y="200" ][s]

*y19
[cm]
#怪異的男人
Fry的中間名是什麼？[p]

[button target="*n20" graphic="ch/49.png" x="0" y="350" ]
[button target="*y20" graphic="ch/48.png" x="0" y="200" ][s]


*n19
[cm]
#怪異的男人
Fry的中間名是什麼？[p]

[button target="*n20" graphic="ch/49.png" x="0" y="350" ]
[button target="*n20" graphic="ch/48.png" x="0" y="200" ][s]





*y20
[cm]
#怪異的男人

通過測試了！[p]
那么我告辭了。[lr]
現在她就給你了。[p]
[chara_hide name="sub" time="100" ]
[_]（男人離去了[p]
[chara_mod name="body" time="100" storage="s/body/stand-t.png" ]
[chara_mod name="sub" time="1" storage="00.png" ]
#少女
再次初次見面、我叫希露薇。[lr]
在這個版本你可以隨意的和我玩。[p]
本來REBEL是打算把我畫成非常樂觀開朗的樣子做開場。[p]
[chara_mod name="body" time="100" storage="s/body/stand-c.png" ]
但是他懶得畫就放棄了所以我還是和原版一樣愁眉苦臉。[p]
[chara_mod name="body" time="100" storage="s/body/stand-t.png" ]
其實本來有女孩子要給我做摸摸頭時的台詞CV的。[lr]
但是她覺得累、堅持不住就放棄了。[p]
[stop_bgm][black][chara_stop]

[jump storage="intro/step1.ks" target="*step1" ]


*n20
[cm]
#怪異的男人
[chara_mod name="sub" time="1" storage="o/sub/def.png" ]
對不起[lr]
你有題目回答錯誤。[lr]
她不能給你。[lr]
遊戲結束。[p]
[black]
[_]（男人帶希露薇離開了[p]
[jump storage="sys/system.ks" target="*game_over" ]




