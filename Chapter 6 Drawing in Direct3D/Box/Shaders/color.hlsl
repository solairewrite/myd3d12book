//***************************************************************************************
// color.hlsl by Frank Luna (C) 2015 All Rights Reserved.
//
// Transforms and colors geometry.
//***************************************************************************************

cbuffer cbPerObject : register(b0)
{
	float4x4 gWorldViewProj;
};

struct VertexIn
{
	// ���� "POSITION" ��Ӧ D3D12_INPUT_ELEMENT_DESC �� "POSITION"
	// D3D12_INPUT_ELEMENT_DESC ͨ���Ⱥ�˳���Ӧ Vertex �ṹ���е�����
	float3 PosL  : POSITION;
	float4 Color : COLOR;
};

struct VertexOut
{
	// SV: System Value, �������εĶ�����ɫ�����Ԫ�ش�����βü��ռ��еĶ���λ����Ϣ
	// ����Ϊ���λ����Ϣ�Ĳ������� SV_POSITION ����
	float4 PosH  : SV_POSITION;
	float4 Color : COLOR;
};

VertexOut VS(VertexIn vin)
{
	VertexOut vout;

	// Transform to homogeneous clip space.
	vout.PosH = mul(float4(vin.PosL, 1.0f), gWorldViewProj);

	// Just pass vertex color into the pixel shader.
	vout.Color = vin.Color;

	return vout;
}

// �ڹ�դ���ڼ�(Ϊ�����μ���������ɫ)�Զ�����ɫ��(�򼸺���ɫ��)����Ķ������Խ��в�ֵ
// ���,�ٽ���Щ��ֵ���ݴ���������ɫ������Ϊ��������
// SV_Target: ����ֵ������Ӧ������ȾĿ���ʽ��ƥ��(�����ֵ�ᱻ������ȾĿ��֮��)
float4 PS(VertexOut pin) : SV_Target
{
	return pin.Color;
}
