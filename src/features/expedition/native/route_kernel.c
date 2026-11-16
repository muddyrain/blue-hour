/* Exact JPS ordering follows Godot 4.7.2 (ed1daf0bf), core/math/a_star_grid_2d.cpp
 * and core/templates/sort_array.h. Godot algorithm portions:
 * Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md).
 * Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 * of the Software, and to permit persons to whom the Software is furnished to do
 * so, subject to the following conditions:
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */
#include "gdextension_interface.h"
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <limits.h>

typedef struct { float g, f; int parent, index; uint32_t open, closed; } Point;
typedef struct {
    int w, h, n, heap_size; uint32_t pass;
    uint8_t *solid, *forced;
    int *ray[4], *diagonal[4], *row, *column, *heap, *output;
    Point *points;
} Kernel;
static const int DX[8] = {0,1,0,-1,-1,1,1,-1};
static const int DY[8] = {-1,0,1,0,-1,-1,1,1};
static int walk(const Kernel *k, int x, int y) {
    return x >= 0 && y >= 0 && x < k->w && y < k->h && !k->solid[y*k->w+x];
}
static void clear_kernel(Kernel *k) {
    free(k->solid); free(k->forced); free(k->row); free(k->column);
    free(k->heap); free(k->output); free(k->points);
    for (int d=0; d<4; ++d) { free(k->ray[d]); free(k->diagonal[d]); }
    memset(k,0,sizeof(*k));
}
/* Build geometry-only ray/diagonal successor fields in linear time. No route,
 * endpoint pair, receipt, or authorization is stored in these fields. */
static void configure(Kernel *k, const int32_t *a, int count) {
    clear_kernel(k);
    if (count < 3 || a[0]<1 || a[1]<1 || a[0]>INT_MAX/a[1] || a[2]<0 || a[2]>(count-3)/4) return;
    k->w=a[0]; k->h=a[1]; k->n=k->w*k->h;
    k->solid=calloc(k->n,1); k->forced=calloc(k->n,1);
    k->row=malloc(k->n*sizeof(int)); k->column=malloc(k->n*sizeof(int));
    k->heap=malloc(k->n*sizeof(int)); k->output=malloc((size_t)2*k->n*sizeof(int));
    k->points=calloc(k->n,sizeof(Point));
    for (int d=0;d<4;++d) { k->ray[d]=malloc(k->n*sizeof(int)); k->diagonal[d]=malloc(k->n*sizeof(int)); }
    int allocated=k->solid && k->forced && k->row && k->column && k->heap && k->output && k->points;
    for(int d=0;d<4;++d) allocated=allocated && k->ray[d] && k->diagonal[d];
    if (!allocated) { clear_kernel(k); return; }
    for (int r=0;r<a[2];++r) {
        const int32_t *b=a+3+r*4;
        if(b[0]<0 || b[1]<0 || b[2]<0 || b[3]<0 || b[0]>k->w-b[2] || b[1]>k->h-b[3]) { clear_kernel(k); return; }
        for(int y=b[1];y<b[1]+b[3];++y) memset(k->solid+y*k->w+b[0],1,b[2]);
    }
    /* Connected runs let a ray test a goal without rescanning any cells. */
    int run=0;
    for(int y=0;y<k->h;++y) { ++run; for(int x=0;x<k->w;++x) { int p=y*k->w+x; if(k->solid[p]) ++run; k->row[p]=run; } }
    run=0;
    for(int x=0;x<k->w;++x) { ++run; for(int y=0;y<k->h;++y) { int p=y*k->w+x; if(k->solid[p]) ++run; k->column[p]=run; } }
    for(int d=0;d<4;++d) {
        int dx=DX[d],dy=DY[d];
        /* Descending in the direction of travel makes the next cell ready. */
        for(int yi=0;yi<k->h;++yi) for(int xi=0;xi<k->w;++xi) {
            int x=dx>0?k->w-1-xi:xi, y=dy>0?k->h-1-yi:yi, p=y*k->w+x;
            k->ray[d][p]=-1;
            if(k->solid[p]) continue;
            int nx=x+dx, ny=y+dy, n=ny*k->w+nx;
            int opening=(walk(k,nx-dy,ny-dx) && !walk(k,x-dy,y-dx)) || (walk(k,nx+dy,ny+dx) && !walk(k,x+dy,y+dx));
            int next=walk(k,nx,ny);
            if(next) k->ray[d][p]=opening?n:k->ray[d][n];
            if(opening || (next && (k->forced[n] & (1u<<d)))) k->forced[p]|=(1u<<d);
        }
    }
    /* Static diagonal stops include native forced-successor(false), whose
     * last tested cell can precede a blocked forward step. Signed terminals
     * distinguish a jump point from the last cell before a failed diagonal. */
    for(int d=4;d<8;++d) {
        int dx=DX[d],dy=DY[d],slot=d-4;
        for(int yi=0;yi<k->h;++yi) for(int xi=0;xi<k->w;++xi) {
            int x=dx>0?k->w-1-xi:xi, y=dy>0?k->h-1-yi:yi, p=y*k->w+x;
            int *field=k->diagonal[slot]; field[p]=-1;
            if(!walk(k,x,y) || !walk(k,x-dx,y) || !walk(k,x,y-dy)) continue;
            int horizontal=dx>0?1:3, vertical=dy>0?2:0;
            if((walk(k,x+dx,y+dy) && !walk(k,x,y+dy)) || !walk(k,x+dx,y) || (k->forced[p] & ((1u<<horizontal)|(1u<<vertical)))) field[p]=p+1;
            else {
                int nx=x+dx,ny=y+dy;
                int value=walk(k,nx,ny)?field[ny*k->w+nx]:-1;
                field[p]=value==-1?-p-2:value;
            }
        }
    }
}
static int ray(const Kernel *k, int p, int d, int goal) {
    int result=k->ray[d][p];
    int px=p%k->w,py=p/k->w,gx=goal%k->w,gy=goal/k->w;
    int aligned=DX[d]? (py==gy && k->row[p]==k->row[goal] && (gx-px)*DX[d]>0) : (px==gx && k->column[p]==k->column[goal] && (gy-py)*DY[d]>0);
    if(aligned && (result<0 || (DX[d]?(gx-result%k->w)*DX[d]:(gy-result/k->w)*DY[d])<=0)) return goal;
    return result;
}
static int jump(const Kernel *k, int p, int d, int goal) {
    if(d<4) return ray(k,p,d,goal);
    int dx=DX[d],dy=DY[d],fx=p%k->w+dx,fy=p/k->w+dy;
    int encoded=k->diagonal[d-4][fy*k->w+fx];
    if(encoded==-1) return -1;
    int end=encoded>0?encoded-1:-encoded-2, limit=abs(end%k->w-fx), earliest=limit+1;
    int gx=goal%k->w,gy=goal/k->w;
    int t=(gy-fy)*dy;
    if(t>=0 && t<=limit) {
        int x=fx+t*dx,q=(fy+t*dy)*k->w+x;
        if((gx-x)*dx>=0 && k->row[q]==k->row[goal]) earliest=t;
    }
    t=(gx-fx)*dx;
    if(t>=0 && t<=limit && t<earliest) {
        int y=fy+t*dy,q=y*k->w+fx+t*dx;
        if((gy-y)*dy>=0 && k->column[q]==k->column[goal]) earliest=t;
    }
    return earliest<=limit?(fy+earliest*dy)*k->w+fx+earliest*dx:(encoded>0?end:-1);
}
static float cost(const Kernel *k,int a,int b) {
    float dx=(float)abs(a%k->w-b%k->w),dy=(float)abs(a/k->w-b/k->w);
    const float f=(float)(1.4142135623730950488-1.0);
    return dx<dy?f*dx+dy:f*dy+dx;
}
static int worse(const Kernel *k,int a,int b) {
    const Point *x=k->points+a,*y=k->points+b;
    return x->f>y->f || (x->f==y->f && x->g<y->g);
}
static void push(Kernel *k,int hole,int value) {
    int parent=(hole-1)/2;
    while(hole>0 && worse(k,k->heap[parent],value)) {
        k->heap[hole]=k->heap[parent]; k->points[k->heap[hole]].index=hole;
        hole=parent; parent=(hole-1)/2;
    }
    k->heap[hole]=value; k->points[value].index=hole;
}
/* Godot SortArray::adjust_heap selects the right child on an exact tie. */
static void pop(Kernel *k) {
    int length=--k->heap_size,value=k->heap[length],hole=0,child=2;
    while(child<length) {
        if(worse(k,k->heap[child],k->heap[child-1])) --child;
        k->heap[hole]=k->heap[child]; k->points[k->heap[hole]].index=hole;
        hole=child; child=2*(child+1);
    }
    if(child==length) { k->heap[hole]=k->heap[child-1]; k->points[k->heap[hole]].index=hole; hole=child-1; }
    push(k,hole,value);
}
static int search(Kernel *k,int ax,int ay,int bx,int by) {
    if(!k->n || !walk(k,ax,ay) || !walk(k,bx,by)) return 0;
    int from=ay*k->w+ax,to=by*k->w+bx;
    if(++k->pass==0) { memset(k->points,0,k->n*sizeof(Point)); k->pass=1; }
    Point *first=k->points+from;
    first->g=0; first->f=cost(k,from,to); first->parent=-1;
    k->heap_size=1; k->heap[0]=from;
    while(k->heap_size) {
        int p=k->heap[0],x=p%k->w,y=p/k->w;
        if(p==to) {
            int count=0;
            for(int q=to;q>=0;q=k->points[q].parent) k->output[count++]=q;
            for(int i=0;i<count/2;++i) { int a=k->output[i]; k->output[i]=k->output[count-1-i]; k->output[count-1-i]=a; }
            /* Expand IDs only at the ABI boundary; no rounding or resampling. */
            for(int i=count-1;i>=0;--i) { int q=k->output[i]; k->output[2*i]=q%k->w; k->output[2*i+1]=q/k->w; }
            return count*2;
        }
        pop(k); k->points[p].closed=k->pass;
        int sides[4]; for(int d=0;d<4;++d) sides[d]=walk(k,x+DX[d],y+DY[d]);
        for(int d=0;d<8;++d) {
            if(d<4?!sides[d]:(!sides[(d-1)%4] || !sides[d-4] || !walk(k,x+DX[d],y+DY[d]))) continue;
            int e=jump(k,p,d,to);
            if(e<0 || k->points[e].closed==k->pass) continue;
            Point *next=k->points+e;
            float g=k->points[p].g+cost(k,p,e);
            if(next->open!=k->pass) { next->open=k->pass; next->index=k->heap_size; k->heap[k->heap_size++]=e; }
            else if(g>=next->g) continue;
            next->parent=p; next->g=g; next->f=g+cost(k,e,to);
            push(k,next->index,e);
        }
    }
    return 0;
}

/* Thin C ABI binding. The header is generated by the pinned engine at build
 * time; no SDK download, C++ runtime, global singleton, or engine patch. */
typedef struct { uint64_t data[2]; } Packed;
typedef struct { uint64_t data; } Name;
static GDExtensionClassLibraryPtr library;
static GDExtensionInterfaceClassdbConstructObject3 construct_object;
static GDExtensionInterfaceObjectSetInstance set_instance;
static GDExtensionInterfaceClassdbRegisterExtensionClass6 register_class;
static GDExtensionInterfaceClassdbRegisterExtensionClassMethod register_method;
static GDExtensionInterfaceClassdbUnregisterExtensionClass unregister_class;
static GDExtensionInterfaceStringNameNewWithLatin1Chars name_new;
static GDExtensionInterfacePackedInt32ArrayOperatorIndex packed_index;
static GDExtensionInterfacePackedInt32ArrayOperatorIndexConst packed_const_index;
static GDExtensionInterfaceVariantGetType variant_type;
static GDExtensionInterfaceVariantNewNil variant_nil;
static GDExtensionTypeFromVariantConstructorFunc to_packed;
static GDExtensionVariantFromTypeConstructorFunc from_packed;
static GDExtensionPtrConstructor packed_new;
static GDExtensionPtrDestructor packed_destroy, name_destroy;
static GDExtensionPtrBuiltInMethod packed_size, packed_resize;
static Name class_name, parent_name, method_name, empty_name;
static GDExtensionObjectPtr create_instance(void *unused, GDExtensionBool notify) {
    (void)unused; (void)notify;
    Kernel *k=calloc(1,sizeof(Kernel));
    GDExtensionObjectPtr object=construct_object(&parent_name);
    set_instance(object,&class_name,k);
    return object;
}
static void free_instance(void *unused, GDExtensionClassInstancePtr instance) {
    (void)unused; clear_kernel(instance); free(instance);
}
static void route_call(void *unused,GDExtensionClassInstancePtr instance,const GDExtensionConstVariantPtr *args,GDExtensionInt argc,GDExtensionVariantPtr out,GDExtensionCallError *error) {
    (void)unused;
    error->error=GDEXTENSION_CALL_OK;
    if(argc!=1 || variant_type(args[0])!=GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY) {
        error->error=GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; variant_nil(out); return;
    }
    Packed input,result;
    to_packed(&input,(GDExtensionVariantPtr)args[0]);
    int64_t size=0;
    packed_size(&input,NULL,&size,0);
    const int32_t *data=size?packed_const_index(&input,0):NULL;
    Kernel *k=instance;
    int length=0;
    if(size>=3 && data[0]>0) configure(k,data,(int)size);
    else if(size==5 && data[0]==0) length=search(k,data[1],data[2],data[3],data[4]);
    packed_new(&result,NULL);
    int64_t output_size=length,resize_error=0;
    GDExtensionConstTypePtr resize_args[]={&output_size};
    packed_resize(&result,resize_args,&resize_error,1);
    if(length && resize_error==0) memcpy(packed_index(&result,0),k->output,length*sizeof(int32_t));
    from_packed(out,&result);
    packed_destroy(&input); packed_destroy(&result);
}
static void initialize(void *unused,GDExtensionInitializationLevel level) {
    (void)unused;
    if(level!=GDEXTENSION_INITIALIZATION_SCENE) return;
    name_new(&class_name,"FieldRouteKernel",0); name_new(&parent_name,"RefCounted",0);
    name_new(&method_name,"route",0); name_new(&empty_name,"",0);
    GDExtensionClassCreationInfo6 creation={0};
    creation.is_exposed=1; creation.create_instance_func=create_instance; creation.free_instance_func=free_instance;
    register_class(library,&class_name,&parent_name,&creation);
    GDExtensionPropertyInfo result={0}; result.type=GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY;
    result.name=&empty_name; result.class_name=&empty_name;
    uint64_t empty_string=0; result.hint_string=&empty_string;
    GDExtensionClassMethodInfo method={0};
    method.name=&method_name; method.call_func=route_call;
    method.method_flags=GDEXTENSION_METHOD_FLAG_NORMAL|GDEXTENSION_METHOD_FLAG_VARARG;
    method.has_return_value=1; method.return_value_info=&result;
    register_method(library,&class_name,&method);
}
static void deinitialize(void *unused,GDExtensionInitializationLevel level) {
    (void)unused;
    if(level!=GDEXTENSION_INITIALIZATION_SCENE) return;
    unregister_class(library,&class_name);
    name_destroy(&class_name); name_destroy(&parent_name); name_destroy(&method_name); name_destroy(&empty_name);
}
#define LOAD(type,variable,name) variable=(type)get_proc(name)
GDExtensionBool bh_route_init(GDExtensionInterfaceGetProcAddress get_proc,GDExtensionClassLibraryPtr lib,GDExtensionInitialization *init) {
    library=lib;
    LOAD(GDExtensionInterfaceClassdbConstructObject3,construct_object,"classdb_construct_object3");
    LOAD(GDExtensionInterfaceObjectSetInstance,set_instance,"object_set_instance");
    LOAD(GDExtensionInterfaceClassdbRegisterExtensionClass6,register_class,"classdb_register_extension_class6");
    LOAD(GDExtensionInterfaceClassdbRegisterExtensionClassMethod,register_method,"classdb_register_extension_class_method");
    LOAD(GDExtensionInterfaceClassdbUnregisterExtensionClass,unregister_class,"classdb_unregister_extension_class");
    LOAD(GDExtensionInterfaceStringNameNewWithLatin1Chars,name_new,"string_name_new_with_latin1_chars");
    LOAD(GDExtensionInterfacePackedInt32ArrayOperatorIndex,packed_index,"packed_int32_array_operator_index");
    LOAD(GDExtensionInterfacePackedInt32ArrayOperatorIndexConst,packed_const_index,"packed_int32_array_operator_index_const");
    LOAD(GDExtensionInterfaceVariantGetType,variant_type,"variant_get_type");
    LOAD(GDExtensionInterfaceVariantNewNil,variant_nil,"variant_new_nil");
    GDExtensionInterfaceGetVariantToTypeConstructor to=(GDExtensionInterfaceGetVariantToTypeConstructor)get_proc("get_variant_to_type_constructor");
    GDExtensionInterfaceGetVariantFromTypeConstructor from=(GDExtensionInterfaceGetVariantFromTypeConstructor)get_proc("get_variant_from_type_constructor");
    GDExtensionInterfaceVariantGetPtrConstructor constructor=(GDExtensionInterfaceVariantGetPtrConstructor)get_proc("variant_get_ptr_constructor");
    GDExtensionInterfaceVariantGetPtrDestructor destructor=(GDExtensionInterfaceVariantGetPtrDestructor)get_proc("variant_get_ptr_destructor");
    GDExtensionInterfaceVariantGetPtrBuiltinMethod builtin=(GDExtensionInterfaceVariantGetPtrBuiltinMethod)get_proc("variant_get_ptr_builtin_method");
    to_packed=to(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY); from_packed=from(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY);
    packed_new=constructor(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY,0);
    packed_destroy=destructor(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY); name_destroy=destructor(GDEXTENSION_VARIANT_TYPE_STRING_NAME);
    Name size_name,resize_name;
    name_new(&size_name,"size",0); name_new(&resize_name,"resize",0);
    packed_size=builtin(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY,&size_name,3173160232);
    packed_resize=builtin(GDEXTENSION_VARIANT_TYPE_PACKED_INT32_ARRAY,&resize_name,848867239);
    name_destroy(&size_name); name_destroy(&resize_name);
    init->minimum_initialization_level=GDEXTENSION_INITIALIZATION_SCENE;
    init->initialize=initialize; init->deinitialize=deinitialize; init->userdata=NULL;
    return 1;
}
