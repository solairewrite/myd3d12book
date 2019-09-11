#include "LightingUtil.hlsl"

Texture2D gDiffuseMap : register(t0);

SamplerState gsamPointWrap : register(s0);
SamplerState gsamPointClamp : register(s1);
SamplerState gsamLinearWrap : register(s2);
SamplerState gsamLinearClamp : register(s3);
SamplerState gsamAnisotropicWrap : register(s4);
SamplerState gsamAnisotropicClamp : register(s5);

cbuffer cbPerObject : register(b0)
{
    float4x4 gWorld;
    float4x4 gTexTransform;
};

cbuffer cbPass : register(b1)
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

    float4 gFogColor;
    float gFogStart;
    float gFogRange;
    float2 cbPerObjectPad2;
	
    Light gLights[MaxLights];
};

cbuffer cbMaterial : register(b2)
{
    float4 gDiffuseAlbedo;
    float3 gFresnelR0;
    float gRoughness;
    float4x4 gMatTransform;
};

struct VertexIn
{
    float3 PosL : POSITION;
};

struct VertexOut
{
    float3 PosL : POSITION;
};

VertexOut VS(VertexIn vin)
{
    VertexOut vout;
	
    vout.PosL = vin.PosL;

    return vout;
}
 
struct PatchTess // ��Ƭϸ��
{
    float EdgeTess[4] : SV_TessFactor; // ��Ե����ϸ������
    float InsideTess[2] : SV_InsideTessFactor; // �ڲ�����ϸ������
};

// ���������ɫ��,���ÿ����Ƭ���д���,������������ϸ������
PatchTess ConstantHS(InputPatch<VertexOut, 4> patch, uint patchID : SV_PrimitiveID)
{
    PatchTess pt;
	
	// ���ĵ�����
    float3 centerL = 0.25f * (patch[0].PosL + patch[1].PosL + patch[2].PosL + patch[3].PosL);
    float3 centerW = mul(float4(centerL, 1.0f), gWorld).xyz;
	
    float d = distance(centerW, gEyePosW);
	
	// ����������۲��ľ���������Ƭ������Ƕ����
	// ���d>=d1,����Ƕ����Ϊ0,��d<=d0,��ô��Ƕ����Ϊ64
	// [d0, d1]����������ִ����Ƕ�����ľ��뷶Χ

    const float d0 = 20.0f;
    const float d1 = 100.0f;
    float tess = 64.0f * saturate((d1 - d) / (d1 - d0));

	// Uniformly tessellate the patch.
	// ����Ƭ�ĸ�����(��Ե,�ڲ�)����ͳһ����Ƕ������

    pt.EdgeTess[0] = tess;
    pt.EdgeTess[1] = tess;
    pt.EdgeTess[2] = tess;
    pt.EdgeTess[3] = tess;
	
    pt.InsideTess[0] = tess;
    pt.InsideTess[1] = tess;
	
    return pt;
}

struct HullOut
{
    float3 PosL : POSITION;
};

// ���Ƶ������ɫ��,�Դ����Ŀ��Ƶ���Ϊ���������
[domain("quad")] // ��Ƭ������
[partitioning("integer")] // ϸ��ģʽ
[outputtopology("triangle_cw")] // ͨ��ϸ������������������,������˳ʱ��
[outputcontrolpoints(4)] // �����ɫ��ִ�еĴ���,ÿ��ִ�ж����1�����Ƶ�
[patchconstantfunc("ConstantHS")] // ָ�����������ɫ���������Ƶ��ַ���
[maxtessfactor(64.0f)] // ����ϸ�����ӵ����ֵ
HullOut HS(InputPatch<VertexOut, 4> p, // InputPatch: ����Ƭ�����е㶼���������ɫ��
           uint i : SV_OutputControlPointID, // ���ڱ������ɫ���������������Ƶ�
           uint patchId : SV_PrimitiveID)
{
    HullOut hout;
	
    hout.PosL = p[i].PosL;
	
    return hout;
}

struct DomainOut
{
    float4 PosH : SV_POSITION;
};

// ÿ����Ƕ����������ʱ�����������ɫ��
// ���԰���������Ƕ����׶κ��"������ɫ��"
[domain("quad")]
DomainOut DS(PatchTess patchTess, // ����ϸ������
             float2 uv : SV_DomainLocation, // ��Ƕ�������Ķ���λ����Ƭ��ռ�(patch domain space)�ڵĲ�������
             const OutputPatch<HullOut, 4> quad)
{
    DomainOut dout;
	
	// Bilinear interpolation.
	// ˫���Բ�ֵ
    float3 v1 = lerp(quad[0].PosL, quad[1].PosL, uv.x);
    float3 v2 = lerp(quad[2].PosL, quad[3].PosL, uv.x);
    float3 p = lerp(v1, v2, uv.y);
	
	// Displacement mapping
	// λ����ͼ
    p.y = 0.3f * (p.z * sin(p.x) + p.x * cos(p.z));
	
    float4 posW = mul(float4(p, 1.0f), gWorld);
    dout.PosH = mul(posW, gViewProj);
	
    return dout;
}

float4 PS(DomainOut pin) : SV_Target
{
    return float4(1.0f, 1.0f, 1.0f, 1.0f);
}
