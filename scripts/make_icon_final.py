import sys
from PIL import Image, ImageDraw, ImageFont
S=1024
FONT=sys.argv[1]; out=sys.argv[2]
def font(size,w=700):
    f=ImageFont.truetype(FONT,size,layout_engine=ImageFont.Layout.RAQM)
    try: f.set_variation_by_axes([w])
    except Exception: pass
    return f
def grad(top,bot):
    img=Image.new("RGB",(S,S)); d=ImageDraw.Draw(img)
    for y in range(S):
        t=y/(S-1); d.line([(0,y),(S,y)],fill=tuple(int(top[i]+(bot[i]-top[i])*t) for i in range(3)))
    return img.convert("RGBA")
def make(name, accent=None):
    img=grad((56,61,72),(24,27,33))
    L=Image.new("RGBA",(S,S),(0,0,0,0)); d=ImageDraw.Draw(L)
    f=font(520)
    l,t,r,b=d.textbbox((0,0),"ض",font=f,direction="rtl")
    d.text(((S-(r-l))/2-l,385-(b-t)/2-t),"ض",font=f,fill=(255,255,255,255),direction="rtl")
    keyc=(255,255,255,70)
    w,h,g=118,92,26
    # row 1: 6 keys
    n=6; x0=(S-(n*w+(n-1)*g))/2; y=665
    for i in range(n):
        x=x0+i*(w+g); d.rounded_rectangle([x,y,x+w,y+h],radius=22,fill=keyc)
    # row 2: small, space bar, small
    y=y+h+g; sw=118*2+g*1
    xs=[x0, x0+w+g, x0+2*(w+g), x0+4*(w+g)+0, x0+5*(w+g)]
    d.rounded_rectangle([x0,y,x0+w,y+h],radius=22,fill=keyc)
    sx=x0+w+g; ex=x0+5*(w+g)-g
    d.rounded_rectangle([sx,y,ex,y+h],radius=22,fill=accent or (255,255,255,110))
    d.rounded_rectangle([x0+5*(w+g),y,x0+5*(w+g)+w,y+h],radius=22,fill=keyc)
    Image.alpha_composite(img,L).convert("RGB").save(f"{out}/{name}.png")
make("concept-e")
make("concept-f",accent=(32,178,150,255))
