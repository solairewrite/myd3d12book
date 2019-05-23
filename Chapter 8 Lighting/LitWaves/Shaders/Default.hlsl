//***************************************************************************************
// Default.hlsl by Frank Luna (C) 2015 All Rights Reserved.
//
// Default shader, currently supports lighting. Ĭ����ɫ��,Ŀǰ��֧�ֹ���
//***************************************************************************************

// Defaults for number of lights. ��Դ������Ĭ��ֵ
#ifndef NUM_DIR_LIGHTS
    #define NUM_DIR_LIGHTS 1
#endif

#ifndef NUM_POINT_LIGHTS
    #define NUM_POINT_LIGHTS 0
#endif

#ifndef NUM_SPOT_LIGHTS
    #define NUM_SPOT_LIGHTS 0
#endif

// Include structures and functions for lighting. �����˹������õĽṹ���뺯��
#include "LightingUtil.hlsl"

// Constant data that varies per frame. ÿ֡���б仯�ĳ�������

cbuffer cbPerObject : register(b0)
{
    float4x4 gWorld;
};

// ÿ�ֲ��ʵĲ�ͬ��������
cbuffer cbMaterial : register(b1)
{
	float4 gDiffuseAlbedo;
    float3 gFresnelR0;
    float  gRoughness;
	float4x4 gMatTransform;
};

// Constant data that varies per material. ���ƹ��������õ����������
cbuffer cbPass : register(b2)
{
    float4x4 gView;
    float4x4 gInvView;
    float4x4 gProj;
    float4x4 gInvProj;
    float4x4 gViewProj;
    float4x4 gInvViewProj;
    float3 gEyePosW;
    float cbPerObjectPad1;
    float2 gRenderTargetSize;
    float2 gInvRenderTargetSize;
    float gNearZ;
    float gFarZ;
    float gTotalTime;
    float gDeltaTime;
    float4 gAmbientLight;

    // Indices [0, NUM_DIR_LIGHTS) are directional lights;
    // indices [NUM_DIR_LIGHTS, NUM_DIR_LIGHTS+NUM_POINT_LIGHTS) are point lights;
    // indices [NUM_DIR_LIGHTS+NUM_POINT_LIGHTS, NUM_DIR_LIGHTS+NUM_POINT_LIGHT+NUM_SPOT_LIGHTS)
    // are spot lights for a maximum of MaxLights per object.
    Light gLights[MaxLights];
};
 
struct VertexIn
{
	float3 PosL    : POSITION;
    float3 NormalL : NORMAL;
};

struct VertexOut
{
	float4 PosH    : SV_POSITION;
    float3 PosW    : POSITION;
    float3 NormalW : NORMAL;
};

VertexOut VS(VertexIn vin)
{
	VertexOut vout = (VertexOut)0.0f;
	
    // Transform to world space.
    float4 posW = mul(float4(vin.PosL, 1.0f), gWorld);
    vout.PosW = posW.xyz;

    // Assumes nonuniform scaling; otherwise, need to use inverse-transpose of world matrix.
	// ����������е��ǵȱ�����,������Ҫʹ������������ת�þ���
    vout.NormalW = mul(vin.NormalL, (float3x3)gWorld);

    // Transform to homogeneous clip space. ������任����βü��ռ�
    vout.PosH = mul(posW, gViewProj);

    return vout;
}

float4 PS(VertexOut pin) : SV_Target
{
    // Interpolating normal can unnormalize it, so renormalize it. 
	// �Է��߽��в�ֵ���ܵ�����ǹ淶��,�����Ҫ�ٴζ������й淶������
    pin.NormalW = normalize(pin.NormalW);

    // Vector from point being lit to eye. ���浽�۲������
    float3 toEyeW = normalize(gEyePosW - pin.PosW);

	// Indirect lighting. ��ӹ���
    float4 ambient = gAmbientLight*gDiffuseAlbedo;

	// ֱ�ӹ���
    const float shininess = 1.0f - gRoughness;
    Material mat = { gDiffuseAlbedo, gFresnelR0, shininess };
    float3 shadowFactor = 1.0f;
    float4 directLight = ComputeLighting(gLights, mat, pin.PosW,
        pin.NormalW, toEyeW, shadowFactor);

    float4 litColor = ambient + directLight;

    // Common convention to take alpha from diffuse material. ������������л�ȡalphaֵ�ĳ����ֶ�
    litColor.a = gDiffuseAlbedo.a;

    return litColor;
}


